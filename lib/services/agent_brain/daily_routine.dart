import 'dart:convert';

import 'package:moodiary/presentation/pref.dart';

import 'behavior_observations.dart';

/// 作息时段 — 用户在一天 24 小时里自定义的「时间段 → 身份 → 做什么」。
///
/// 这是「行为作息」的计划线：用户自己描述每天大致在每个时间段以什么身份
/// 在做什么（如 23:00–8:00 睡觉、上午打游戏、下午学习），智能体再用手机
/// 观察（[BehaviorObservationStore]）监督是否照做，两条线共同拼出真实行为。
///
/// 时间用「当日分钟数 0..1439」表示（整数运算，排序/包含/跨天/重叠零成本）：
/// - 普通时段：endMinute > startMinute（end 不包含，允许相邻时段）
/// - 跨天时段：endMinute < startMinute（如 23:00→08:00，回绕包含到次日）
/// - 全天时段：endMinute == startMinute（任意时刻命中）
class RoutineSlot {
  final String id;

  /// 开始分钟 0..1439。
  final int startMinute;

  /// 结束分钟 0..1439；<= startMinute 表示跨天（== 表示全天）。
  final int endMinute;

  /// 该时段身份（如「学生」）；空则回落顶层 defaultIdentity。
  final String identity;

  /// 该时段在做什么（如「睡觉」「学习」）。
  final String activity;

  /// 可选备注（v1 模型预留，UI 不暴露）。
  final String note;

  const RoutineSlot({
    required this.id,
    required this.startMinute,
    required this.endMinute,
    this.identity = '',
    this.activity = '',
    this.note = '',
  });

  bool get isFullDay => startMinute == endMinute;
  bool get isCrossDay => endMinute < startMinute;

  /// 某分钟是否落在本时段（含跨天回绕 / 全天）。
  bool contains(int minute) {
    if (isFullDay) return true;
    if (isCrossDay) return minute >= startMinute || minute < endMinute;
    return minute >= startMinute && minute < endMinute;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'identity': identity,
        'activity': activity,
        'note': note,
      };

  factory RoutineSlot.fromJson(Map<String, dynamic> j) => RoutineSlot(
        id: j['id']?.toString() ?? 'r${DateTime.now().millisecondsSinceEpoch}',
        startMinute: (j['startMinute'] as num?)?.toInt() ?? 0,
        endMinute: (j['endMinute'] as num?)?.toInt() ?? 1440,
        identity: j['identity']?.toString() ?? '',
        activity: j['activity']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
      );
}

/// 整份作息表：顶层日常身份 + 按开始时间排序的时段列表。
class RoutineSchedule {
  String defaultIdentity;
  List<RoutineSlot> slots;

  RoutineSchedule({this.defaultIdentity = '', List<RoutineSlot>? slots})
      : slots = slots ?? [];

  /// 按开始分钟、再按结束分钟升序。
  List<RoutineSlot> get sorted {
    final list = [...slots];
    list.sort((a, b) {
      final c = a.startMinute.compareTo(b.startMinute);
      return c != 0 ? c : a.endMinute.compareTo(b.endMinute);
    });
    return list;
  }

  Map<String, dynamic> toJson() => {
        'defaultIdentity': defaultIdentity,
        'slots': slots.map((s) => s.toJson()).toList(),
      };

  factory RoutineSchedule.fromJson(Map<String, dynamic> j) => RoutineSchedule(
        defaultIdentity: j['defaultIdentity']?.toString() ?? '',
        slots: (j['slots'] as List?)
                ?.whereType<Map>()
                .map((e) => RoutineSlot.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
      );
}

/// 作息表存储 — PrefUtil JSON 侧表（key=dailyRoutine），与 behaviorObservations
/// / dailyRhythm 同款模式，走 WebDAV 快同步。
class DailyRoutineStore {
  static const String _prefKey = 'dailyRoutine';

  static Future<RoutineSchedule> load() async {
    final s = PrefUtil.getValue<String>(_prefKey);
    if (s == null || s.isEmpty) return RoutineSchedule();
    try {
      return RoutineSchedule.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return RoutineSchedule();
    }
  }

  static Future<void> save(RoutineSchedule schedule) async {
    await PrefUtil.setValue<String>(
        _prefKey, jsonEncode(schedule.toJson()));
  }

  /// 分钟 → 'HH:mm'（1380 → '23:00'）。
  static String fmtMm(int minute) {
    final m = ((minute % 1440) + 1440) % 1440;
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mi = (m % 60).toString().padLeft(2, '0');
    return '$h:$mi';
  }

  /// 时段文本：'23:00–次日08:00' / '08:00–12:00' / '00:00–次日00:00（全天）'。
  static String fmtSlot(RoutineSlot s) {
    if (s.isFullDay) return '${fmtMm(s.startMinute)}–次日${fmtMm(s.endMinute)}（全天）';
    if (s.isCrossDay) return '${fmtMm(s.startMinute)}–次日${fmtMm(s.endMinute)}';
    return '${fmtMm(s.startMinute)}–${fmtMm(s.endMinute)}';
  }

  /// 当前时刻命中的时段（取最晚开始的命中；重叠已在 UI 层拦截，实际唯一）。
  static RoutineSlot? slotAt(RoutineSchedule s, DateTime t) {
    final m = t.hour * 60 + t.minute;
    RoutineSlot? hit;
    for (final slot in s.sorted) {
      if (slot.contains(m)) hit = slot;
    }
    return hit;
  }

  /// 该时段展示用的身份（回落 defaultIdentity → '我'）。
  static String _identityOf(RoutineSchedule s, RoutineSlot slot) {
    if (slot.identity.trim().isNotEmpty) return slot.identity.trim();
    if (s.defaultIdentity.trim().isNotEmpty) return s.defaultIdentity.trim();
    return '我';
  }

  /// 作息表的自然语言文本（AI 注入 / UI 预览用）。
  static String summaryText(RoutineSchedule s) {
    final slots = s.sorted;
    if (slots.isEmpty) return '（未定义作息表）';
    final buf = StringBuffer();
    if (s.defaultIdentity.trim().isNotEmpty) {
      buf.writeln('日常身份：${s.defaultIdentity.trim()}');
    }
    for (final slot in slots) {
      final act = slot.activity.trim().isEmpty ? '（未填）' : slot.activity.trim();
      buf.writeln('- ${fmtSlot(slot)}：${_identityOf(s, slot)} $act');
    }
    return buf.toString().trim();
  }

  /// 当前时刻应处于的文本：'学生·睡觉'；无命中 → '未定义当前时段'。
  static String currentSlotText(RoutineSchedule s, DateTime t) {
    final slot = slotAt(s, t);
    if (slot == null) return '未定义当前时段';
    final act = slot.activity.trim().isEmpty ? '（未填）' : slot.activity.trim();
    return '${_identityOf(s, slot)}·$act';
  }

  /// 手机监督：把用户定义的作息表与近 N 天智能体观察到的实际行为对照。
  ///
  /// 对每个时段按「时间落在该时段」过滤观察，聚合出实际在做什么，并给一个
  /// 轻量的符合/偏离判定（启发式粗分，原始 App×次数保留给 AI 自行裁决）。
  static Future<String> supervisionText(
    RoutineSchedule s, {
    DateTime? now,
    int days = 3,
    int top = 3,
  }) async {
    final t = now ?? DateTime.now();
    if (s.slots.isEmpty) return '（未定义作息表）';
    final all = await BehaviorObservationStore.load();
    final cutoff = t.subtract(Duration(days: days));
    final recent = all.where((o) => o.time.isAfter(cutoff)).toList();
    if (recent.isEmpty) return '（近$days天无行为观察数据）';

    final buf = StringBuffer();
    for (final slot in s.sorted) {
      final inWindow = recent
          .where((o) => slot.contains(o.time.hour * 60 + o.time.minute))
          .toList();
      final label = '${fmtSlot(slot)}（${_identityOf(s, slot)}·${slot.activity.trim().isEmpty ? '（未填）' : slot.activity.trim()}）';
      if (inWindow.isEmpty) {
        buf.writeln('- $label：近$days天无此时段观察（可能未用手机/睡眠/断网）');
        continue;
      }
      final counts = <String, int>{};
      var distract = 0;
      for (final o in inWindow) {
        final a = o.activity.isEmpty ? '（${o.event}）' : o.activity;
        counts[a] = (counts[a] ?? 0) + 1;
        if (o.focusClass == 'distract') distract++;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topStrs =
          sorted.take(top).map((e) => '${e.key}×${e.value}').join('、');
      final verdict = _verdict(slot, sorted.first.key, distract, inWindow.length);
      buf.writeln('- $label：近$days天观察 ${inWindow.length} 次 → $topStrs$verdict');
    }
    return buf.toString().trim();
  }

  /// 轻量判定：文本命中→符合；计划要求专注但观察偏娱乐→偏离；其余中性。
  static String _verdict(
      RoutineSlot slot, String dominant, int distract, int n) {
    final plan = slot.activity.trim();
    if (plan.isNotEmpty && (dominant.contains(plan) || plan.contains(dominant))) {
      return ' → 符合（实际行为匹配计划）';
    }
    final productive =
        RegExp(r'(学习|上课|工作|写作|读书|锻炼|健身|开会|编程|复习|作业)')
            .hasMatch(plan);
    if (productive && n > 0 && distract > n / 2) {
      return ' → 偏离（计划「$plan」应专注，但实际观察偏娱乐）';
    }
    return ' → 未明显冲突（AI 可结合上下文判断）';
  }

  /// 时段重叠检测（分钟集合求交；端点互斥，允许相邻时段）。
  static bool hasOverlap(List<RoutineSlot> existing, RoutineSlot c) {
    if (c.isFullDay && existing.isNotEmpty) return true;
    final cs = _minuteSet(c);
    return existing.any((o) => _minuteSet(o).intersection(cs).isNotEmpty);
  }

  static Set<int> _minuteSet(RoutineSlot s) {
    if (s.isFullDay) return {for (var m = 0; m < 1440; m++) m};
    if (s.isCrossDay) {
      return {for (var m = s.startMinute; m < 1440; m++) m}
          .union({for (var m = 0; m < s.endMinute; m++) m});
    }
    return {for (var m = s.startMinute; m < s.endMinute; m++) m};
  }
}
