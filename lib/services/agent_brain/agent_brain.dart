import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';
import 'package:moodiary/services/memory_service.dart';
import 'package:moodiary/utils/environment_sensor.dart';

import 'agent_rule.dart';
import 'agent_task.dart';

/// 大脑信号 — 代码机械监督 / 用户规则 / 任务变化 送入大脑的输入。
///
/// [type]：信号类型（weather_changed / diary_stable / usage_category_changed /
///        profile_uninitialized / user_rule ...），用于冷却节流。
/// [summary]：给大脑看的自然语言描述。
/// [data]：附加结构化数据（如天气快照）。
class BrainSignal {
  final String type;
  final String summary;
  final Map<String, dynamic> data;

  BrainSignal({
    required this.type,
    required this.summary,
    this.data = const {},
  });
}

/// 智能体大脑 — 收到信号后决定「要不要做、做什么」，把行动拆成任务写库。
///
/// 闭环：信号/规则 → [handleSignal] 决策 → AgentTaskStore 落库 →
/// BrainService 轮询分发 → AgentExecutor 执行 → 反馈 → [processFeedback] 收口。
class AgentBrain {
  static const String _cooldownKey = 'brainCooldowns';

  /// 同类信号冷却时长（防止每个信号都烧一次 AI 调用）
  static const Duration signalCooldown = Duration(hours: 6);

  /// 大脑可规划的合法动作（与 AgentExecutor 分发一致）
  static const List<String> validActions = [
    'tts',
    'start_chat',
    'ask_user',
    'block_screen',
    'update_profile',
    'analyze_diaries',
  ];

  static const List<String> validKinds = [
    'immediate',
    'scheduled',
    'longterm',
  ];

  /// 处理一个信号：冷却 → 组装上下文 → AI 决策 → 写任务库。
  ///
  /// [force]：跳过冷却（实验室页手动触发用）。返回决策摘要（供日志/UI 展示）。
  static Future<String> handleSignal(BrainSignal signal,
      {bool force = false}) async {
    if (!force && await _isCoolingDown(signal.type)) {
      return '信号 ${signal.type} 冷却中，跳过（6 小时内不重复处理）';
    }

    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      print('[AgentBrain] AI 未配置，跳过信号 ${signal.type}');
      return 'AI 未配置，跳过大脑决策';
    }

    final context = await _buildContext(signal);
    final base = await AiPromptManager().loadPrompt('brain_plan.txt');
    final system = '$base\n\n---- 以下是本次决策的上下文 ----\n\n$context';

    final String raw;
    try {
      final stream = await provider.chat(messages: [
        AIMessage(role: 'system', content: system),
        AIMessage(role: 'user', content: '请根据当前输入决策。'),
      ]);
      final sb = StringBuffer();
      await for (final chunk in stream) {
        sb.write(chunk);
      }
      raw = sb.toString().trim();
    } catch (e) {
      // 打上脱敏后的 key 与响应状态，方便从日志定位「旧 key / 换服务商」问题
      final resp = e is DioException
          ? ' HTTP ${e.response?.statusCode} ${e.response?.statusMessage}'
          : '';
      print('[AgentBrain] AI 决策失败 ${provider.config.baseUrl} '
          'key=${_maskKey(provider.config.apiKey)}$resp: $e');
      return '大脑 AI 调用失败，跳过本次信号';
    }
    if (raw.isEmpty) return '大脑未返回内容';

    final parsed = _parsePlan(raw);
    await _markHandled(signal.type);

    String summary;
    if (parsed.noop) {
      summary = '大脑判断无需行动：${parsed.reason}';
      print('[AgentBrain] 信号 ${signal.type} → noop: ${parsed.reason}');
    } else {
      final created = <String>[];
      for (final t in parsed.tasks) {
        final task = _taskFromJson(t);
        if (task == null) continue;
        await AgentTaskStore.add(task);
        created.add(task.title);
      }
      summary = created.isEmpty
          ? '大脑没有生成有效任务'
          : '已生成任务：${created.join('；')}';
      print('[AgentBrain] 信号 ${signal.type} → 生成 ${created.length} 个任务');
    }

    // 记录本次决策的输入/输出（实验室「大脑输入/输出」监督面板读取）
    await _recordDecision(
      signal,
      input: context,
      output: raw,
      noop: parsed.noop,
      reason: parsed.reason,
      taskCount: parsed.tasks.length,
      summary: summary,
    );
    return summary;
  }

  /// 记录一次大脑决策的完整输入/输出到 PrefUtil（key=brainLastDecision）。
  ///
  /// 实验室页据此展示「送进大脑的上下文」与「模型原始输出」，让用户
  /// 能验证输入是否真正成功、决策依据是什么。
  static Future<void> _recordDecision(
    BrainSignal signal, {
    required String input,
    required String output,
    required bool noop,
    required String reason,
    required int taskCount,
    required String summary,
  }) async {
    final data = jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'signalType': signal.type,
      'signalSummary': signal.summary,
      'input': input,
      'output': output,
      'noop': noop,
      'reason': reason,
      'taskCount': taskCount,
      'summary': summary,
    });
    await PrefUtil.setValue<String>('brainLastDecision', data);
    print('[AgentBrain] 决策已记录: ${signal.type} noop=$noop tasks=$taskCount');
  }

  /// 处理用户对某个任务的反馈：写入反馈 → AI 决定「结束 / 继续等待」。
  static Future<String> processFeedback(String taskId, String feedback) async {
    final task = await AgentTaskStore.byId(taskId);
    if (task == null) return '任务不存在: $taskId';

    task.feedback = [...task.feedback, '[${_hm(DateTime.now())}] $feedback'];
    await AgentTaskStore.update(task);

    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      task.status = 'done';
      await AgentTaskStore.update(task);
      return 'AI 未配置，任务「${task.title}」标记完成';
    }

    final prompt = '''
你是 Moodsonder 智能体大脑。你正在处理一个任务的用户反馈，判断该任务是否已解决。
任务：${task.title}
类型：${task.kind} / ${task.action}
历史反馈：
${task.feedback.join('\n')}
用户最新反馈：$feedback
判断规则：
- 若用户已明确回应、认可，或给出了足以完成任务的信息 → decision=done
- 若任务需要用户继续配合、或问题仍待解决 → decision=wait
- 若任务已无意义 → decision=done
输出严格 JSON（不要其他内容）：{"decision":"done|wait","reason":"简短理由"}''';

    var decision = 'done';
    var reason = '';
    try {
      final stream = await provider.chat(messages: [
        AIMessage(role: 'user', content: prompt),
      ]);
      final sb = StringBuffer();
      await for (final chunk in stream) {
        sb.write(chunk);
      }
      final parsed = _parseDecision(sb.toString().trim());
      decision = parsed.decision;
      reason = parsed.reason;
    } catch (e) {
      print('[AgentBrain] 反馈决策失败: $e');
    }

    if (decision == 'wait') {
      task.status = 'waitingUser';
      task.feedback = [...task.feedback, '[大脑] 继续等待：$reason'];
      await AgentTaskStore.update(task);
      return '任务「${task.title}」继续等待用户回应';
    }

    // 任务解决：若是 ask_user（如第一次沟通问基础认知），
    // 把用户回答经 AI 提炼后沉淀进画像（姓名/年龄/身份落库）。
    var insight = '';
    if (task.action == 'ask_user') {
      final question = task.params['question']?.toString() ?? '';
      insight = await MemoryService.ingestChatInsight(question, feedback);
      task.feedback = [
        ...task.feedback,
        if (insight.isNotEmpty) '[画像] $insight',
      ];
    }

    task.status = 'done';
    task.feedback = [...task.feedback, '[大脑] 任务已解决：$reason'];
    await AgentTaskStore.update(task);
    return '任务「${task.title}」已结束${insight.isNotEmpty ? '（$insight）' : ''}';
  }

  /// 助手对话 hook：用户发来一条消息时，把最早的 waitingUser 任务当作反馈处理。
  /// 无等待任务时返回 null（调用方继续正常对话）。
  static Future<String?> processWaitingUserFeedback(String userMessage) async {
    final waiting = await AgentTaskStore.query(status: 'waitingUser');
    if (waiting.isEmpty) return null;
    final oldest = waiting.first; // query 按 priority 降序、createdAt 升序 → 最早创建
    return await processFeedback(oldest.id, userMessage);
  }

  // ─── 上下文组装 ───────────────────────────────────────

  static Future<String> _buildContext(BrainSignal signal) async {
    final buf = StringBuffer();
    final now = DateTime.now();
    const wd = ['一', '二', '三', '四', '五', '六', '日'];
    buf.writeln(
        '【当前时间】${now.year}年${now.month}月${now.day}日 星期${wd[now.weekday - 1]} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
    buf.writeln('【信号】类型: ${signal.type}');
    buf.writeln('描述: ${signal.summary}');
    if (signal.data.isNotEmpty) {
      buf.writeln('附加数据: ${jsonEncode(signal.data)}');
    }
    buf.writeln();

    // 当前环境（天气信号相关，且对决策有用）
    try {
      final snap = await EnvironmentSensor.getSnapshot();
      if (snap != null) {
        final city = '${snap['province']}${snap['city']}${snap['district']}';
        buf.writeln(
            '【当前环境】$city，天气${snap['weather']}，${snap['temp']}℃');
      } else {
        buf.writeln('【当前环境】获取失败');
      }
    } catch (_) {
      buf.writeln('【当前环境】获取失败');
    }

    try {
      final dayStart = DateTime(now.year, now.month, now.day);
      final diaries = await IsarUtil.getDiariesByDateRange(
          dayStart, dayStart.add(const Duration(hours: 23, minutes: 59)));
      buf.writeln('【今天日记数】${diaries.length} 篇');
    } catch (_) {}

    buf.writeln();
    final profile = await MemoryService.getProfile();
    buf.writeln('【用户画像】${profile.isEmpty ? '（暂无，未初始化）' : profile}');
    buf.writeln();

    final pending = await AgentTaskStore.query(status: 'pending');
    final running = await AgentTaskStore.query(status: 'running');
    final waiting = await AgentTaskStore.query(status: 'waitingUser');
    final active = [...pending, ...running, ...waiting];
    if (active.isEmpty) {
      buf.writeln('【待办任务库】（空）');
    } else {
      buf.writeln('【待办任务库】');
      for (final t in active) {
        final at = t.scheduledAt != null ? ' @${_hm(t.scheduledAt!)}' : '';
        buf.writeln('- [${t.status}] ${t.title}（${t.action}$at）');
      }
    }
    buf.writeln();

    final rules = await AgentRuleStore.load();
    if (rules.isEmpty) {
      buf.writeln('【用户规则】（暂无）');
    } else {
      buf.writeln('【用户规则】');
      for (final r in rules) {
        buf.writeln('- $r');
      }
    }
    return buf.toString();
  }

  // ─── 宽松解析 ─────────────────────────────────────────

  /// 解析大脑规划输出。容忍 ```json 围栏与前后杂文。
  static ({bool noop, String reason, List<Map<String, dynamic>> tasks})
      _parsePlan(String raw) {
    String text = raw.trim();
    text = text.replaceFirst(RegExp(r'^```(json)?\s*'), '').trim();
    text = text.replaceFirst(RegExp(r'\s*```$'), '').trim();

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final m = jsonDecode(text.substring(start, end + 1)) as Map;
        if (m['noop'] == true) {
          return (
            noop: true,
            reason: m['reason']?.toString() ?? '',
            tasks: <Map<String, dynamic>>[],
          );
        }
        final list = m['tasks'] as List? ?? [];
        return (
          noop: false,
          reason: '',
          tasks: list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      } catch (_) {
        // fallthrough → noop
      }
    }
    return (
      noop: true,
      reason: '输出解析失败',
      tasks: <Map<String, dynamic>>[],
    );
  }

  /// 把大脑输出的任务 JSON 转成 AgentTask；非法则返回 null。
  static AgentTask? _taskFromJson(Map<String, dynamic> j) {
    final title = j['title']?.toString().trim();
    if (title == null || title.isEmpty) return null;
    final kind = validKinds.contains(j['kind']) ? j['kind'] as String : 'immediate';
    final action = j['action']?.toString();
    if (action == null || !validActions.contains(action)) return null;

    DateTime? scheduledAt;
    final sa = j['scheduledAt']?.toString();
    if (sa != null && sa.isNotEmpty) {
      scheduledAt = DateTime.tryParse(sa);
    }

    return AgentTask(
      title: title,
      kind: kind,
      action: action,
      params: (j['params'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          ) ??
          const {},
      status: 'pending',
      scheduledAt: scheduledAt,
      priority: (j['priority'] as num?)?.toInt() ?? 0,
    );
  }

  /// 解析反馈决策输出。
  static ({String decision, String reason}) _parseDecision(String raw) {
    String text = raw.trim();
    text = text.replaceFirst(RegExp(r'^```(json)?\s*'), '').trim();
    text = text.replaceFirst(RegExp(r'\s*```$'), '').trim();

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final m = jsonDecode(text.substring(start, end + 1)) as Map;
        final d = m['decision']?.toString() == 'wait' ? 'wait' : 'done';
        return (decision: d, reason: m['reason']?.toString() ?? '');
      } catch (_) {
        // fallthrough
      }
    }
    return (decision: 'done', reason: '');
  }

  // ─── 冷却 ─────────────────────────────────────────────

  static Future<bool> _isCoolingDown(String type) async {
    final c = await _loadCooldowns();
    final last = c[type];
    if (last == null) return false;
    return DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(last))
            .inMilliseconds <
        signalCooldown.inMilliseconds;
  }

  static Future<void> _markHandled(String type) async {
    final c = await _loadCooldowns();
    c[type] = DateTime.now().millisecondsSinceEpoch;
    await PrefUtil.setValue<String>(_cooldownKey, jsonEncode(c));
  }

  static Future<Map<String, int>> _loadCooldowns() async {
    final s = PrefUtil.getValue<String>(_cooldownKey);
    if (s == null || s.isEmpty) return {};
    try {
      return (jsonDecode(s) as Map)
          .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 脱敏 key：只显示前 8 位与长度，日志可安全携带。
  static String _maskKey(String key) => key.isEmpty
      ? '(空)'
      : '${key.length > 8 ? key.substring(0, 8) : key}…(${key.length})';
}
