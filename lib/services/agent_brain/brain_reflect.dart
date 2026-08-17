import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/services/memory_service.dart';

import 'agent_task.dart';

/// 执行后反思 — 大脑的「学习回路」（第三层：让规划越用越贴合用户）。
///
/// 任务到达终态后复盘一次它的经过与用户反应，把「什么对用户有效/无效」
/// 提炼成画像要点沉淀进【用户画像】，供下次规划参考。
///
/// 约束：
/// - 只反思**能观察到用户反应**的任务：ask_user / start_chat / block_screen
///   的完成态，以及任何被取消的任务（失败时间线里有信息）；
///   静默动作（update_profile / analyze_diaries）无用户信号，不反思。
/// - 全局节流 20 分钟一次（控制 AI 成本）；已反思过的任务不重复。
class BrainReflect {
  static const String _throttleKey = 'brainReflectLastAt';
  static const Duration _globalThrottle = Duration(minutes: 20);

  /// 有用户可观察反应的动作（它们的 done 才值得复盘）
  static const List<String> _reflectActions = [
    'ask_user',
    'start_chat',
    'block_screen',
  ];

  /// 任务终态后调用：满足条件则做一次轻量复盘并沉淀画像（失败静默）。
  static Future<void> maybeReflect(AgentTask task) async {
    try {
      final latest = await AgentTaskStore.byId(task.id);
      if (latest == null) return;
      // 只复盘终态（done/cancelled）；waitingUser 等用户回应期间不碰
      if (latest.status != 'done' && latest.status != 'cancelled') return;
      final isCancelled = latest.status == 'cancelled';
      if (!isCancelled && !_reflectActions.contains(latest.action)) return;
      if (latest.feedback.any((f) => f.contains('[反思]'))) return; // 已反思
      if (!_cooledDown()) return;

      final provider = AiProviderManager().currentProvider;
      if (provider == null || !provider.isConfigured) return;

      final profile = await MemoryService.getProfile();
      final base = await AiPromptManager().loadPrompt('brain_reflect.txt');
      final persona = await AiPromptManager().loadPersona();
      // 角色卡注入：反思也是 Sonder 本人，但输出必须遵循下方严格 JSON
      final system = persona.isNotEmpty
          ? '【角色卡 · 你的人格】\n$persona\n\n'
              '你始终是 Sonder 本人，但这里是复盘场景：输出必须严格遵循下方 JSON 格式，'
              '不要在 aspects 里添加表情或语气词。\n\n$base'
          : base;
      final input = '''
任务：${latest.title}
类型：${latest.kind} / ${latest.action} / 终态 ${latest.status}
参数：${latest.params}
执行时间线：
${latest.feedback.join('\n')}
当前画像：
${profile.isEmpty ? '（暂无）' : profile}''';

      final stream = await provider.chat(messages: [
        AIMessage(role: 'system', content: system),
        AIMessage(role: 'user', content: input),
      ]);
      final sb = StringBuffer();
      await for (final c in stream) {
        sb.write(c);
      }
      final aspects = _parseAspects(sb.toString().trim());

      String summary = '';
      if (aspects.isNotEmpty) {
        // 反思提炼的洞察来源记为 pattern_recognition（从任务经过中识别出的行为规律）
        final data = await MemoryService.mergeAspects(aspects,
            source: 'pattern_recognition');
        summary = '沉淀 ${data.totalCount} 条画像';
      }
      await _markReflected();
      latest.feedback = [
        ...latest.feedback,
        '[反思] ${summary.isEmpty ? '未沉淀新洞察' : summary}',
      ];
      await AgentTaskStore.update(latest);
      print('[BrainReflect] 反思完成: ${latest.title} → $summary');
    } catch (e) {
      print('[BrainReflect] 反思失败: $e');
    }
  }

  /// 宽容解析反思输出：容忍 ```json 围栏，取 aspects 数组。
  static List<String> _parseAspects(String raw) {
    String text = raw.trim();
    text = text.replaceFirst(RegExp(r'^```(json)?\s*'), '').trim();
    text = text.replaceFirst(RegExp(r'\s*```$'), '').trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final m = jsonDecode(text.substring(start, end + 1)) as Map;
        final list = m['aspects'] as List? ?? [];
        return list.whereType<String>().toList();
      } catch (_) {}
    }
    return [];
  }

  static bool _cooledDown() {
    final last = PrefUtil.getValue<String>(_throttleKey);
    if (last == null) return true;
    final t = DateTime.tryParse(last);
    if (t == null) return true;
    return DateTime.now().difference(t) >= _globalThrottle;
  }

  static Future<void> _markReflected() async {
    await PrefUtil.setValue<String>(
        _throttleKey, DateTime.now().toIso8601String());
  }
}
