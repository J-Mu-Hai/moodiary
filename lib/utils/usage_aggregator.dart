import '../common/models/isar/usage_record.dart';

/// 屏幕使用时间：把 Android 平台通道返回的原始数据聚合为按天分组的 UsageRecord。
/// 纯函数，可单测。
///
/// 入参每项形如 `{ 'dayKey': '2026/8/8', 'packageName': 'com.x', 'appName': 'X', 'totalMs': 12345 }`。
/// 返回 `Map<dayKey, List<UsageRecord>>`，dayKey 形如 `'2026/8/8'`。
Map<String, List<UsageRecord>> groupUsageByDay(
  List<Map<String, dynamic>> raw, {
  DateTime? now,
}) {
  final result = <String, List<UsageRecord>>{};
  final nowTs = now ?? DateTime.now();
  for (final item in raw) {
    final dayKey = item['dayKey'] as String? ?? '';
    if (dayKey.isEmpty) continue;
    // 平台通道可能返回 int/double/字符串，统一容错解析
    final rawTotal = item['totalMs'];
    final totalMs = rawTotal is num
        ? rawTotal.toInt()
        : (rawTotal == null ? 0 : int.tryParse('$rawTotal') ?? 0);
    if (totalMs <= 0) continue;
    final date = dayStartFromKey(dayKey);
    if (date == null) continue;
    final packageName = item['packageName'] as String? ?? '';
    result.putIfAbsent(dayKey, () => []).add(UsageRecord()
      ..id = usageRecordId(date, packageName)
      ..date = date
      ..packageName = packageName
      ..appName = item['appName'] as String? ?? ''
      ..foregroundMs = totalMs
      ..lastModified = nowTs);
  }
  return result;
}

/// `'2026/8/8'` → 当天零点 DateTime；解析失败返回 null。
DateTime? dayStartFromKey(String dayKey) {
  final parts = dayKey.split('/');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}
