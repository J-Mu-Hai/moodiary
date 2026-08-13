import 'package:isar/isar.dart';

part 'usage_session.g.dart';

/// 一段前台使用会话：`[start, end)` 内 [packageName] 处于前台。
///
/// 由采集端（Android）把 `queryEvents` 的原始事件流（进入/退出前台、
/// 锁屏、熄屏）配对成一段段会话后写入；`end == null` 表示会话仍在进行中。
/// 电脑端（Windows）只读展示/同步，不采集。
///
/// 这一集合是"时间线""一天中时间分配""精确监督"共同的数据地基：
/// 按天求和 [durationMs] 就是总时长，按 [start] 排序就是时间线，
/// 单条会话本身就是分钟级的监督记录。
@collection
class UsageSession {
  /// 业务主键：`<startMillis>_<包名>`，确定性生成。
  ///
  /// 与 [UsageRecord] 同理：同一段会话重新拉取时用同一 id，`put` 覆盖而
  /// 不新增，避免 WebDAV/本地文件无限累积。（生成函数见文件底部。）
  @Index()
  String id = '';

  @Id()
  int get isarId => fastHash(id);

  /// 年月日索引（与 Diary/UsageRecord 一致的字符串键，用于按天查询）
  @Index()
  String get yMd => '${start.year}/${start.month}/${start.day}';

  /// 会话开始时刻（该应用进入前台的时刻）
  @Index()
  DateTime start = DateTime.now();

  /// 会话结束时刻；`null` 表示该会话仍在进行中
  @Index()
  DateTime? end;

  /// 应用包名
  String packageName = '';

  /// 应用名称（解析失败的兜底为包名）
  String appName = '';

  /// 上次更新时间（重算会话时用于覆盖判断）
  @Index()
  DateTime lastModified = DateTime.now();

  UsageSession();

  /// 会话时长（毫秒）。进行中的会话按"现在 - 开始"估算。
  int get durationMs {
    final e = end;
    final t = e ?? DateTime.now();
    final d = t.difference(start).inMilliseconds;
    return d < 0 ? 0 : d;
  }

  /// 是否仍在进行中
  bool get isOpen => end == null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'start': start.toIso8601String(),
      'end': end?.toIso8601String(),
      'packageName': packageName,
      'appName': appName,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory UsageSession.fromJson(Map<String, dynamic> json) {
    final endStr = json['end'] as String?;
    return UsageSession()
      ..id = json['id'] as String
      ..start = DateTime.parse(json['start'] as String)
      ..end = endStr == null ? null : DateTime.parse(endStr)
      ..packageName = json['packageName'] as String
      ..appName = json['appName'] as String? ?? ''
      ..lastModified = DateTime.parse(json['lastModified'] as String);
  }
}

/// 生成确定性会话 id：`<startMillis>_<包名>`。
String usageSessionId(DateTime start, String packageName) =>
    '${start.millisecondsSinceEpoch}_$packageName';

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
