import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

part 'guide_message.g.dart';

/// AI 引导式任务规划的对话记录（按日记持久化，跨重启续聊）。
///
/// [diaryId] 关联 `Diary.id`（uuid 字符串，跨重启稳定）。
/// [kind] 区分气泡形态：text / stageComplete / systemNotice。
@collection
class GuideMessage {
  // 业务主键，使用 uuid
  String id = const Uuid().v7();

  // 数据库主键，使用 hash 业务主键
  @Id()
  int get isarId => fastHash(id);

  // 归属日记 id（Diary.id）
  @Index()
  String diaryId = '';

  // 消息角色：user | assistant
  String role = 'assistant';

  // 气泡类型：text | stageComplete | systemNotice
  String kind = 'text';

  // 气泡文本（assistant 消息可能含 [[ACTION:..]] 标记）
  String content = '';

  // stageComplete 的 JSON payload
  String extra = '';

  // 消息产生时的引导阶段（1..7，8=完成）
  int stage = 1;

  // 消息时间
  @Index()
  DateTime ts = DateTime.now();

  GuideMessage();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'diaryId': diaryId,
      'role': role,
      'kind': kind,
      'content': content,
      'extra': extra,
      'stage': stage,
      'ts': ts.toIso8601String(),
    };
  }

  factory GuideMessage.fromJson(Map<String, dynamic> json) {
    return GuideMessage()
      ..id = json['id'] as String
      ..diaryId = json['diaryId'] as String
      ..role = json['role'] as String
      ..kind = json['kind'] as String
      ..content = json['content'] as String
      ..extra = json['extra'] as String
      ..stage = json['stage'] as int
      ..ts = DateTime.parse(json['ts'] as String);
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
