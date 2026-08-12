import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

part 'usage_record.g.dart';

/// 屏幕使用时间记录：某天某应用的前台使用时长。
///
/// 采集端（Android）通过 UsageStatsManager 聚合写入；同步端通过
/// WebDAV `/Moodiary/Usage/` 与电脑端互通。电脑端只读展示，不采集。
@collection
class UsageRecord {
  // 业务主键，使用 uuid
  @Index()
  String id = const Uuid().v7();

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
