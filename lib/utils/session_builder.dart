import '../common/models/isar/usage_session.dart';

/// UsageEvents 事件类型常量（与 Android 端保持一致）。
class UsageEventType {
  static const int activityResumed = 1;
  static const int activityPaused = 2;
  static const int screenNonInteractive = 5;
  static const int screenInteractive = 6;
  static const int keyguardShown = 11;
  static const int keyguardHidden = 12;
}

/// 把增量事件流构建成一段段前台会话。纯函数，可单测。
///
/// [rawEvents] 形如 `[{ 't': 毫秒, 'pkg': 'com.x', 'type': 1 }]`，已按时间升序。
/// [initialOpen] 是库里现存"进行中"的会话（其开始时刻可能早于本次拉取的游标，
/// 所以必须从库里取回作为起始前台态，否则它永远无法被后续退出事件闭合）。
///
/// 返回 `(closed, open)`：
/// - closed：已闭合的会话（end 已填好），直接 put 覆盖即可；
/// - open：最终仍在进行中的会话（end == null），可能为 null。
///
/// 规则：
/// - RESUME(pkg)：若前台态已是 pkg 则跳过；否则闭合当前前台态、以 pkg 开启新会话。
/// - PAUSE(pkg) / 熄屏 / 锁屏：若前台态是 pkg 则闭合它；前台态为空时忽略
///   （可能是更早会话的尾巴，由下一次 RESUME 兜底闭合，不会产生脏数据）。
({List<UsageSession> closed, UsageSession? open}) buildSessionsFromEvents(
  List<Map<String, dynamic>> rawEvents, {
  required DateTime now,
  UsageSession? initialOpen,
}) {
  UsageSession? current = initialOpen;
  final closed = <UsageSession>[];

  for (var i = 0; i < rawEvents.length; i++) {
    final raw = rawEvents[i];
    final tRaw = raw['t'];
    final typeRaw = raw['type'];
    final pkg = raw['pkg'] as String? ?? '';
    if (tRaw is! num || typeRaw is! num || pkg.isEmpty) continue;

    final type = typeRaw.toInt();
    final t = DateTime.fromMillisecondsSinceEpoch(tRaw.toInt());

    if (type == UsageEventType.activityResumed) {
      if (current != null && current.packageName == pkg) continue; // 已是前台态
      if (current != null) {
        _close(current, t, now);
        closed.add(current);
      }
      current = UsageSession()
        ..id = usageSessionId(t, pkg)
        ..start = t
        ..packageName = pkg
        ..appName = ''
        ..lastModified = now;
    } else if (current != null && current.packageName == pkg) {
      // PAUSE / 熄屏 / 锁屏。
      // 熄屏（screenNonInteractive）一定是真结束：屏幕关了使用必然中断。
      // PAUSE / 锁屏 则可能是"同应用内部 activity 切换"或"拉通知栏后立刻回来"，
      // 若紧接着的下一个有效事件是同包 RESUME，说明前台从未真正离开该应用，
      // 忽略这次退出 —— 否则一段连续使用会被切成一条条一两分钟的碎片。
      final isScreenOff = type == UsageEventType.screenNonInteractive;
      final transient =
          !isScreenOff && _isTransientIntraAppPause(rawEvents, i, pkg);
      if (transient) continue;
      _close(current, t, now);
      closed.add(current);
      current = null;
    }
    // 前台态为空时的退出事件忽略（见规则说明）
  }

  return (closed: closed, open: current);
}

/// 从事件 [i] 之后向前看：若下一个"有效事件"是同包 RESUME，则这次 PAUSE 只是
/// 同应用内部页面切换（A 页面 → B 页面），前台并未真正离开，返回 true。
/// 有效事件 = RESUME / 熄屏 / 锁屏；其余（连续 PAUSE、KEYGUARD_HIDDEN、
/// SCREEN_INTERACTIVE 等）跳过继续向前看，直到遇到 RESUME 或真退出事件。
bool _isTransientIntraAppPause(
  List<Map<String, dynamic>> rawEvents,
  int i,
  String pkg,
) {
  for (var j = i + 1; j < rawEvents.length; j++) {
    final e = rawEvents[j];
    final typeRaw = e['type'];
    final nextPkg = e['pkg'] as String? ?? '';
    if (typeRaw is! num || nextPkg.isEmpty) continue;
    final type = typeRaw.toInt();
    if (type == UsageEventType.activityResumed) return nextPkg == pkg;
    if (type == UsageEventType.screenNonInteractive ||
        type == UsageEventType.keyguardShown) {
      return false; // 真的离开前台了（熄屏/锁屏），不是瞬时切换
    }
  }
  return false; // 事件流结束仍无同包 RESUME，按真退出处理
}

void _close(UsageSession s, DateTime end, DateTime now) {
  s.end = end;
  s.lastModified = now;
}
