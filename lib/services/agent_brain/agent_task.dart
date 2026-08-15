import 'dart:convert';
import 'dart:math';

import 'package:moodiary/presentation/pref.dart';

/// 智能体任务 — 大脑「规划 → 执行 → 反馈」闭环的最小单元。
///
/// 每个任务都是「一个需要解决的事」：
/// - [kind]：immediate（及时，立刻执行）/ scheduled（定时，到点执行）/
///           longterm（长期，存入任务规划持续追踪）
/// - [action]：执行器能力（tts / start_chat / ask_user / block_screen / update_profile）
/// - [status]：pending（待执行）/ running（执行中）/ waitingUser（等用户回应）/
///             done（完成）/ cancelled（取消）
///
/// 存储用 PrefUtil（SharedPreferences）JSON blob（与 MemoryService 同款模式），
/// 体量小（任务几十条），无需引入新 Isar 集合。
class AgentTask {
  String id;
  String title;

  /// immediate | scheduled | longterm
  String kind;

  /// tts | start_chat | ask_user | block_screen | update_profile
  String action;

  /// action 参数：text / question / durationMinutes / reason / taskId ...
  Map<String, dynamic> params;

  /// pending | running | waitingUser | done | cancelled
  String status;

  /// 定时任务的执行时刻（kind==scheduled 时有效）
  DateTime? scheduledAt;

  /// 优先级（数值越大越优先）
  int priority;

  /// 执行/用户回应产生的反馈记录（历史追加）
  List<String> feedback;

  DateTime createdAt;
  DateTime updatedAt;

  AgentTask({
    String? id,
    required this.title,
    required this.kind,
    required this.action,
    this.params = const {},
    this.status = 'pending',
    this.scheduledAt,
    this.priority = 0,
    this.feedback = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _genId(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static String _genId() {
    final rnd = Random();
    return 't${DateTime.now().millisecondsSinceEpoch}${rnd.nextInt(0xffff).toRadixString(16)}';
  }

  bool get isPending => status == 'pending';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind,
        'action': action,
        'params': params,
        'status': status,
        'scheduledAt': scheduledAt?.toIso8601String(),
        'priority': priority,
        'feedback': feedback,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AgentTask.fromJson(Map<String, dynamic> json) => AgentTask(
        id: json['id']?.toString(),
        title: json['title']?.toString() ?? '(无标题)',
        kind: json['kind']?.toString() ?? 'immediate',
        action: json['action']?.toString() ?? 'tts',
        params: (json['params'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v),
            ) ??
            const {},
        status: json['status']?.toString() ?? 'pending',
        scheduledAt: DateTime.tryParse(json['scheduledAt']?.toString() ?? ''),
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        feedback: (json['feedback'] as List?)?.cast<String>() ?? [],
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// 任务库 — 大脑产出任务的持久化存取与查询。
class AgentTaskStore {
  static const String _prefKey = 'agentTasks';

  static Future<List<AgentTask>> load() async {
    final jsonStr = PrefUtil.getValue<String>(_prefKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => AgentTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<AgentTask> tasks) async {
    await PrefUtil.setValue<String>(
        _prefKey, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  static Future<void> add(AgentTask task) async {
    final tasks = await load();
    tasks.add(task);
    await _save(tasks);
  }

  static Future<void> update(AgentTask task) async {
    task.updatedAt = DateTime.now();
    final tasks = await load();
    final idx = tasks.indexWhere((t) => t.id == task.id);
    if (idx != -1) {
      tasks[idx] = task;
      await _save(tasks);
    }
  }

  static Future<void> remove(String id) async {
    final tasks = await load();
    tasks.removeWhere((t) => t.id == id);
    await _save(tasks);
  }

  static Future<AgentTask?> byId(String id) async {
    final tasks = await load();
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 按状态/类型/动作过滤。默认按优先级降序、创建时间升序返回。
  static Future<List<AgentTask>> query({
    String? status,
    String? kind,
    String? action,
  }) async {
    final tasks = await load();
    final filtered = tasks.where((t) {
      if (status != null && t.status != status) return false;
      if (kind != null && t.kind != kind) return false;
      if (action != null && t.action != action) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final byPri = b.priority.compareTo(a.priority);
        return byPri != 0 ? byPri : a.createdAt.compareTo(b.createdAt);
      });
    return filtered;
  }
}
