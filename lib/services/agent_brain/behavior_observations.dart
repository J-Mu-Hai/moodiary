import 'dart:convert';

import 'package:moodiary/presentation/pref.dart';

/// 行为观察条目 — 「什么时间段 → 在做什么 → 效果 → 和哪件任务契合」的时序库。
///
/// 智能体观察者的记忆地基：不只记画像（静态认知），还记「用户在每个时间段
/// 常做什么、效果如何、和哪件任务相关」，供大脑决策时参考用户当下的行为模式。
class BehaviorObservation {
  final String id;

  /// 行为发生时刻。
  final DateTime time;

  /// 时间段标签：早 / 上午 / 中午 / 下午 / 傍晚 / 深夜（见 [BehaviorObservationStore.timeRangeOf]）。
  final String timeRange;

  /// 星期几（DateTime.weekday，1=周一 … 7=周日）。
  final int weekday;

  /// 事件类型：使用App | 完成任务 | 专注结束 | 自我报告。
  final String event;

  /// 具体在做什么（App 名 / 任务标题 / 用户自述的一句话）。
  final String activity;

  /// App 类别（使用App 观察时；其他事件可为空）。
  final String category;

  /// 专注属性：focus | distract | neutral（娱乐/非娱乐分类轴）。
  final String focusClass;

  /// 持续时长（毫秒；App 会话 / 专注时长）。
  final int? durationMs;

  /// 效果评分 0..1（完成任务/锁屏的成败，null=未评价）。
  final double? effect;

  /// 关联任务 id（完成任务 / 锁屏）。
  final String? taskId;

  /// 关联任务标题。
  final String? taskTitle;

  /// 与任务的契合度 0..1（null=未评价）。
  final double? taskFit;

  /// 置信度 0..1（代码机械采集低，用户自述高）。
  final double confidence;

  final DateTime createdAt;

  BehaviorObservation({
    required this.id,
    required this.time,
    required this.timeRange,
    required this.weekday,
    required this.event,
    required this.activity,
    this.category = '',
    this.focusClass = 'neutral',
    this.durationMs,
    this.effect,
    this.taskId,
    this.taskTitle,
    this.taskFit,
    this.confidence = 0.6,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? time;

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'timeRange': timeRange,
        'weekday': weekday,
        'event': event,
        'activity': activity,
        'category': category,
        'focusClass': focusClass,
        'durationMs': durationMs,
        'effect': effect,
        'taskId': taskId,
        'taskTitle': taskTitle,
        'taskFit': taskFit,
        'confidence': confidence,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BehaviorObservation.fromJson(Map<String, dynamic> j) {
    final t = DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now();
    return BehaviorObservation(
      id: j['id']?.toString() ?? 'o${t.millisecondsSinceEpoch}',
      time: t,
      timeRange: j['timeRange']?.toString() ?? BehaviorObservationStore.timeRangeOf(t),
      weekday: (j['weekday'] as num?)?.toInt() ?? t.weekday,
      event: j['event']?.toString() ?? '使用App',
      activity: j['activity']?.toString() ?? '',
      category: j['category']?.toString() ?? '',
      focusClass: j['focusClass']?.toString() ?? 'neutral',
      durationMs: (j['durationMs'] as num?)?.toInt(),
      effect: (j['effect'] as num?)?.toDouble(),
      taskId: j['taskId']?.toString(),
      taskTitle: j['taskTitle']?.toString(),
      taskFit: (j['taskFit'] as num?)?.toDouble(),
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.6,
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? ''),
    );
  }
}

/// 行为观察存储 — PrefUtil JSON 侧表（key=behaviorObservations，追加式列表，
/// 只保留 90 天），与 diaryAiRead / agentTasks 同款模式。
class BehaviorObservationStore {
  static const String _prefKey = 'behaviorObservations';

  static Future<List<BehaviorObservation>> load() async {
    final s = PrefUtil.getValue<String>(_prefKey);
    if (s == null || s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .whereType<Map>()
          .map((e) => BehaviorObservation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<BehaviorObservation> list) async {
    await PrefUtil.setValue<String>(
        _prefKey, jsonEncode(list.map((o) => o.toJson()).toList()));
  }

  /// 追加一条观察（新→旧），只保留 90 天。
  static Future<void> record({
    required String event,
    required String activity,
    String category = '',
    String focusClass = 'neutral',
    int? durationMs,
    double? effect,
    String? taskId,
    String? taskTitle,
    double? taskFit,
    double confidence = 0.6,
    DateTime? time,
  }) async {
    final list = await load();
    final t = time ?? DateTime.now();
    final obs = BehaviorObservation(
      id: 'o${t.millisecondsSinceEpoch}${list.length}',
      time: t,
      timeRange: timeRangeOf(t),
      weekday: t.weekday,
      event: event,
      activity: activity,
      category: category,
      focusClass: focusClass,
      durationMs: durationMs,
      effect: effect,
      taskId: taskId,
      taskTitle: taskTitle,
      taskFit: taskFit,
      confidence: confidence,
    );
    list.insert(0, obs);
    await _save(trimBefore90d(list));
  }

  static List<BehaviorObservation> trimBefore90d(List<BehaviorObservation> list) {
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    return list.where((o) => o.time.isAfter(cutoff)).toList();
  }

  static Future<List<BehaviorObservation>> recent({int limit = 20}) async {
    final list = await load();
    return list.take(limit).toList();
  }

  /// 「时间段 → 在做什么 → 次数」的行为模板（只统计实际使用行为）。
  static Future<Map<String, Map<String, int>>> aggregateByTimeRange() async {
    final list = await load();
    final out = <String, Map<String, int>>{};
    for (final o in list) {
      if (o.event != '使用App') continue;
      final m = out.putIfAbsent(o.timeRange, () => {});
      m[o.activity] = (m[o.activity] ?? 0) + 1;
    }
    return out;
  }

  /// 当前时间段常做行为的文本（大脑上下文注入用，列出常见时间段 top 行为）。
  static Future<String> topBehaviorsText(DateTime now, {int top = 3}) async {
    final agg = await aggregateByTimeRange();
    if (agg.isEmpty) return '（暂无模板）';
    final tr = timeRangeOf(now);
    final ordered = <String>[tr, ...agg.keys.where((k) => k != tr)];
    final lines = <String>[];
    for (final range in ordered) {
      final counts = agg[range];
      if (counts == null || counts.isEmpty) continue;
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final parts =
          sorted.take(top).map((e) => '${e.key}×${e.value}').join('、');
      lines.add('- $range：$parts');
      if (lines.length >= 3) break;
    }
    return lines.join('\n');
  }

  /// 最近 N 条观察的文本（大脑上下文注入用）。
  static Future<String> recentText({int limit = 3}) async {
    final list = await recent(limit: limit);
    if (list.isEmpty) return '（暂无）';
    final buf = StringBuffer();
    for (final o in list) {
      final dur = o.durationMs != null ? '，${fmtDuration(o.durationMs!)}' : '';
      final eff = o.effect != null ? '，效果${(o.effect! * 10).round()}/10' : '';
      buf.writeln('- ${o.timeRange} ${o.activity}（${o.event}$dur$eff）');
    }
    return buf.toString().trim();
  }

  /// 小时 → 时间段。
  static String timeRangeOf(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 8) return '早';
    if (h >= 8 && h < 11) return '上午';
    if (h >= 11 && h < 13) return '中午';
    if (h >= 13 && h < 17) return '下午';
    if (h >= 17 && h < 21) return '傍晚';
    return '深夜';
  }

  static String fmtDuration(int ms) {
    final m = (ms / 60000).round();
    if (m < 1) return '<1分钟';
    return m < 60 ? '$m分钟' : '${m ~/ 60}小时${m % 60}分钟';
  }
}
