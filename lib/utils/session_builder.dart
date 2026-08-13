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

  for (final raw in rawEvents) {
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
      // PAUSE / 熄屏 / 锁屏：闭合当前前台态
      _close(current, t, now);
      closed.add(current);
      current = null;
    }
    // 前台态为空时的退出事件忽略（见规则说明）
  }

  return (closed: closed, open: current);
}

void _close(UsageSession s, DateTime end, DateTime now) {
  s.end = end;
  s.lastModified = now;
}
