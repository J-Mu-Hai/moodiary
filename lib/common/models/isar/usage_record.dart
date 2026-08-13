import 'package:isar/isar.dart';

part 'usage_record.g.dart';

/// 屏幕使用时间记录：某天某应用的前台使用时长。
///
/// 采集端（Android）通过 UsageStatsManager 聚合写入；同步端通过
/// WebDAV `/Moodiary/Usage/` 与电脑端互通。电脑端只读展示，不采集。
@collection
class UsageRecord {
  /// 业务主键：`<日期>-<包名>`，确定性生成。
  ///
  /// 关键设计：id 必须由（日期 + 包名）确定性推导，而不是随机 uuid。
  /// 否则每次重新采集同一天的数据都会生成新 id → 上传到 WebDAV 变成
  /// 新文件 → 服务器文件无限累积 → 同步越跑越慢直到两端卡死。
  /// （`usageRecordId` 定义见文件底部。）
  @Index()
  String id = '';

  // 数据库主键，使用 hash 业务主键
  @Id()
  int get isarId => fastHash(id);

  // 年月日索引（与 Diary/ExpenseRecord 一致的字符串键，用于按天查询）
  @Index()
  String get yMd => '${date.year}/${date.month}/${date.day}';

  // 日期（当天零点）
  @Index()
  DateTime date = DateTime.now();

  // 应用包名
  String packageName = '';

  // 应用名称（解析失败的兜底为包名）
  String appName = '';

  // 前台使用时长（毫秒）
  int foregroundMs = 0;

  // 上次更新时间，用于增量同步
  @Index()
  DateTime lastModified = DateTime.now();

  UsageRecord();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'packageName': packageName,
      'appName': appName,
      'foregroundMs': foregroundMs,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory UsageRecord.fromJson(Map<String, dynamic> json) {
    return UsageRecord()
      ..id = json['id'] as String
      ..date = DateTime.parse(json['date'] as String)
      ..packageName = json['packageName'] as String
      ..appName = json['appName'] as String
      ..foregroundMs = json['foregroundMs'] as int
      ..lastModified = DateTime.parse(json['lastModified'] as String);
  }
}

/// 生成确定性使用记录 id：`2026-08-13_<包名>`。
///
/// 同一天同一个应用恒为同一个 id，`put` 会覆盖而不是新增，从源头
/// 杜绝 WebDAV 服务器文件累积。包名只含 `[a-zA-Z0-9._]`，可安全
/// 用作文件名。
String usageRecordId(DateTime date, String packageName) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}_$packageName';

int fastHash(String string) {
  var hash = 0xcbf29ce484222325;

  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }
  return hash;
}
