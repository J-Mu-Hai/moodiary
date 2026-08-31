import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/ai_provider_manager.dart';

import 'behavior_observations.dart';

/// 智能体对用户「一天 24h 每个时间段大致在做什么、作息节律如何」的一句话行为画像。
///
/// 由 [BehaviorModelStore.build] 从近 N 天 [BehaviorObservationStore] 观察
/// 归纳生成并落库（key=behaviorModel，已加入 PrefUtil.allowList）。与画像
/// （userMemory）不同：这是「可随时重算的派生认知」——每天 23:30 的
/// build_behavior_model 种子任务会重算，旧了不心疼。
class BehaviorModel {
  final String narrative;
  final DateTime updatedAt;

  const BehaviorModel({required this.narrative, required this.updatedAt});

  Map<String, dynamic> toJson() => {
        'narrative': narrative,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory BehaviorModel.fromJson(Map<String, dynamic> j) => BehaviorModel(
        narrative: j['narrative']?.toString() ?? '',
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// 一个分钟窗口的行为聚合结果（纯计算中间结构）。
class BehaviorWindow {
  final int startMinute; // 桶起点 0..1439
  final int endMinute; // 桶终点（开区间）
  final int total; // 窗口内观察条数
  final List<(String, int)> topActivities; // (活动, 次数) 前 top 名
  final int distract; // focusClass=='distract' 条数

  const BehaviorWindow({
    required this.startMinute,
    required this.endMinute,
    required this.total,
    required this.topActivities,
    required this.distract,
  });
}

/// 智能体行为认知库 — 手机观察的确定性聚合（代码现算）+ AI 一句话行为画像（落库）。
///
/// 「行为作息」的用户手动定义已移除（daily_routine.dart 已下线），改由智能体
/// 自主归纳：近 N 天 [BehaviorObservationStore] 观察按分钟窗口聚合成
/// 「每个时间段大致在做什么」，再让模型把整体节律归纳成一句话叙事。这是
/// 智能体框架的「记忆」层：感知（工具）→ 推理（大脑）→ 行动（任务/权限）
/// → 记忆（认知库）的闭环。
class BehaviorModelStore {
  static const String _prefKey = 'behaviorModel';

  /// 建模进行中守卫：防「每日种子任务」与「重新建模按钮」并发重复烧 AI。
  static bool _building = false;

  static Future<BehaviorModel?> load() async {
    final s = PrefUtil.getValue<String>(_prefKey);
    if (s == null || s.isEmpty) return null;
    try {
      return BehaviorModel.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(BehaviorModel m) async {
    await PrefUtil.setValue<String>(_prefKey, jsonEncode(m.toJson()));
  }

  /// 分钟 → 'HH:mm'（1380 → '23:00'）。
  static String fmtMm(int minute) {
    final m = ((minute % 1440) + 1440) % 1440;
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mi = (m % 60).toString().padLeft(2, '0');
    return '$h:$mi';
  }

  /// 分钟窗口聚合：近 [days] 天观察按 [windowMinutes] 一桶切 24h，
  /// 输出每桶 top 活动×次数 + focus/distract 分布。
  static Future<List<BehaviorWindow>> aggregate({
    int days = 7,
    int windowMinutes = 120,
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final cutoff = t.subtract(Duration(days: days));
    final bucketCount = (1440 ~/ windowMinutes).clamp(1, 24);

    final buckets = List.generate(bucketCount, (_) => <String, int>{});
    final totalBuckets = List<int>.filled(bucketCount, 0);
    final distractBuckets = List<int>.filled(bucketCount, 0);

    final all = await BehaviorObservationStore.load();
    for (final o in all) {
      if (!o.time.isAfter(cutoff)) continue;
      final minute = o.time.hour * 60 + o.time.minute;
      final idx = (minute ~/ windowMinutes).clamp(0, bucketCount - 1);
      final a =
          o.activity.trim().isEmpty ? '（${o.event}）' : o.activity.trim();
      buckets[idx][a] = (buckets[idx][a] ?? 0) + 1;
      totalBuckets[idx]++;
      if (o.focusClass == 'distract') distractBuckets[idx]++;
    }

    final out = <BehaviorWindow>[];
    for (var i = 0; i < bucketCount; i++) {
      final sorted = buckets[i].entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      out.add(BehaviorWindow(
        startMinute: i * windowMinutes,
        endMinute: ((i + 1) * windowMinutes).clamp(0, 1440),
        total: totalBuckets[i],
        topActivities: sorted.take(3).map((e) => (e.key, e.value)).toList(),
        distract: distractBuckets[i],
      ));
    }
    return out;
  }

  /// 全部桶的聚合文本（注入 / 函数 / 卡片共用）；空桶跳过保持紧凑。
  static Future<String> aggregationText({
    int days = 7,
    int windowMinutes = 120,
    DateTime? now,
  }) async {
    final buckets =
        await aggregate(days: days, windowMinutes: windowMinutes, now: now);
    final buf = StringBuffer();
    for (final w in buckets) {
      if (w.total == 0) continue;
      final parts = w.topActivities.map((e) => '${e.$1}×${e.$2}').join('、');
      buf.writeln('- ${fmtMm(w.startMinute)}–${fmtMm(w.endMinute)}：$parts'
          '（${w.total}次，娱乐类${w.distract}）');
    }
    if (buf.isEmpty) return '（近$days天暂无行为观察）';
    return buf.toString().trim();
  }

  /// 当前时刻对应窗口的文本。
  static Future<String> currentWindowText(
    DateTime now, {
    int days = 7,
    int windowMinutes = 120,
  }) async {
    final buckets =
        await aggregate(days: days, windowMinutes: windowMinutes, now: now);
    if (buckets.isEmpty) return '（无观察数据）';
    final minute = now.hour * 60 + now.minute;
    final idx = (minute ~/ windowMinutes).clamp(0, buckets.length - 1);
    final w = buckets[idx];
    final span = '${fmtMm(w.startMinute)}–${fmtMm(w.endMinute)}';
    if (w.total == 0) return '$span（近$days天无观察）';
    final parts = w.topActivities.map((e) => '${e.$1}×${e.$2}').join('、');
    return '$span：$parts（${w.total}次，娱乐类${w.distract}）';
  }

  /// 【智能体行为认知】统一注入模板（大脑 / 分析 / 对话 / 主动行为 4 处共用）。
  static Future<String> contextText({
    DateTime? now,
    int days = 7,
    int windowMinutes = 120,
  }) async {
    final t = now ?? DateTime.now();
    final agg =
        await aggregationText(days: days, windowMinutes: windowMinutes, now: t);
    final model = await load();
    final narrative = model == null || model.narrative.isEmpty
        ? '（尚未建模，将自动归纳）'
        : model.narrative;
    final current = await currentWindowText(t,
        days: days, windowMinutes: windowMinutes);
    return '【智能体行为认知】\n'
        '近$days天手机观察（自动归纳）：\n$agg\n'
        '智能体归纳：$narrative\n'
        '当前 ${fmtMm(t.hour * 60 + t.minute)} 对应时段：$current';
  }

  /// 重新归纳行为模型：聚合近 N 天观察 → 模型生成一句话行为画像 → 落库。
  ///
  /// 由 build_behavior_model 任务（每日 23:30 种子）与分析页「重新建模」按钮
  /// 共用。AI 未配置 / 调用失败 / 返回空时保留旧模型，返回结果摘要
  /// （executor 写反馈、卡片 toast 用）。[_building] 防并发双烧 AI。
  static Future<String> build({int days = 7, int windowMinutes = 120}) async {
    if (_building) return '行为建模进行中，请稍候';
    _building = true;
    try {
      final provider = AiProviderManager().currentProvider;
      if (provider == null || !provider.isConfigured) {
        return 'AI 未配置，跳过行为建模';
      }
      final agg =
          await aggregationText(days: days, windowMinutes: windowMinutes);
      final prompt = '''
你是 Moodsonder 智能体。下面是一份手机行为观察的分时段聚合（近$days天）：

$agg

请用 50 字以内的一句话，归纳这个用户「一天 24 小时每个时间段大致在做什么、作息节律如何」
（如：几点睡几点醒、工作/学习时段、娱乐时段、是否熬夜）。只依据上方观察数据，
不要臆断观察里没有的信息。直接输出这句话，不要其他内容。''';
      final stream = await provider.chat(messages: [
        AIMessage(role: 'system', content: prompt),
        AIMessage(role: 'user', content: '请归纳。'),
      ]);
      final sb = StringBuffer();
      await for (final chunk in stream) {
        sb.write(chunk);
      }
      final narrative = sb.toString().trim();
      if (narrative.isEmpty) {
        return '模型未返回内容，行为建模失败（保留旧模型）';
      }
      await save(BehaviorModel(narrative: narrative, updatedAt: DateTime.now()));
      return '行为建模完成：$narrative';
    } catch (e) {
      print('[BehaviorModel] 建模失败: $e');
      return '行为建模失败: $e（保留旧模型）';
    } finally {
      _building = false;
    }
  }
}
