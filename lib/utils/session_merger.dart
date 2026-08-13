import '../common/models/isar/usage_session.dart';

/// 显示层合并：把相邻的"同应用"会话拼成一段，消除时间线碎片化。
///
/// 纯函数，不修改传入列表（输出是新对象）。输入需按开始时刻升序
/// （时间线视图的 `sessions` 即 `getUsageSessionsByDay` 的 `sortByStart()` 结果）。
///
/// 合并条件：两段会话同一包名、都已闭合，且前一段结束与后一段开始的时间差
/// ≤ [maxGap]（默认 2 分钟，覆盖同应用内部页面切换 / 拉通知栏后又回来 /
/// 秒级进出后台等"看起来是碎片"的场景），中间没有被其他应用插队。
/// 合并结果：start 取最早一段、end 取最晚一段，时长由 `durationMs` 派生自动累加。
///
/// 进行中的会话（end == null）不参与合并：它是"当前正在使用"的红点，单独展示
/// 更有信息量；同时避免把数据库里真正的 open 行在显示层丢弃造成语义漂移。
List<UsageSession> mergeAdjacentSessions(
  List<UsageSession> sessions, {
  Duration maxGap = const Duration(minutes: 2),
}) {
  if (sessions.length < 2) return List.of(sessions);
  final merged = <UsageSession>[];
  for (final s in sessions) {
    if (merged.isNotEmpty &&
        merged.last.packageName == s.packageName &&
        _canMerge(merged.last, s, maxGap)) {
      // 合进上一段：end 取更晚一段（s 在后，lastModified 一定更晚）
      merged.last.end = s.end;
      merged.last.lastModified = s.lastModified;
      continue;
    }
    merged.add(_copy(s));
  }
  return merged;
}

bool _canMerge(UsageSession a, UsageSession b, Duration maxGap) {
  if (a.end == null || b.end == null) return false; // 进行中不合并
  if (b.start.isBefore(a.end!)) return true; // 时间重叠（异常数据）也合并
  return b.start.difference(a.end!) <= maxGap;
}

UsageSession _copy(UsageSession s) => UsageSession()
  ..id = s.id
  ..start = s.start
  ..end = s.end
  ..packageName = s.packageName
  ..appName = s.appName
  ..lastModified = s.lastModified;
