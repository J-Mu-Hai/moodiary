import 'dart:async';
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
import 'behavior_observations.dart';
import 'brain_reflect.dart';
import 'brain_service.dart';
import 'daily_rhythm.dart';
import 'daily_routine.dart';
import 'focus_mode.dart';

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

  /// 按日期回溯日志（brainDecisionLog）只保留最近 3 天：
  /// 记录完整输入/输出（不截断），开发阶段观察「智能体每天有什么输入/输出」，
  /// 体积靠时间裁剪控制（满 3 天的旧记录随写入一并丢弃）。
  static const Duration _logRetention = Duration(days: 3);

  /// 大脑可规划的合法动作（与 AgentExecutor 分发一致）
  static const List<String> validActions = [
    'tts',
    'start_chat',
    'ask_user',
    'block_screen',
    'update_profile',
    'analyze_diaries',
    'open_diary',
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
      // 冷却命中也要落日志：让实验室面板能看到「每一次输入都到了大脑」，
      // 直接回应「为什么这个输入没有变成输出」。
      final cd = _cooldownFor(signal.type);
      final window =
          cd.inHours >= 24 ? '${cd.inDays} 天' : '${cd.inMinutes} 分钟';
      await _appendLog({
        'kind': 'signal_skipped',
        'time': DateTime.now().toIso8601String(),
        'signalType': signal.type,
        'summary': '信号到达但冷却中，跳过',
        'input': signal.summary,
        'output': '同类信号 $window 内已处理过，本次不重复决策（冷却保护）。',
      });
      return '信号 ${signal.type} 冷却中，跳过（$window 内不重复处理）';
    }

    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      // AI 未配置也要落日志：否则任何信号都像「没来过」，用户无从排查。
      await _appendLog({
        'kind': 'signal_skipped',
        'time': DateTime.now().toIso8601String(),
        'signalType': signal.type,
        'summary': '信号到达，但 AI 未配置，无法决策',
        'input': signal.summary,
        'output': 'AI 未配置（provider 为空/未配置），跳过大脑决策。请先在设置里配置 AI。',
      });
      print('[AgentBrain] AI 未配置，跳过信号 ${signal.type}');
      return 'AI 未配置，跳过大脑决策';
    }

    final context = await _buildContext(signal);
    final base = await AiPromptManager().loadPrompt('brain_plan.txt');
    final persona = await AiPromptManager().loadPersona();
    // 角色卡注入：规划者也保持同一人格，但输出必须严格遵循 brain_plan 的 JSON
    final personaBlock = persona.isNotEmpty
        ? '【角色卡 · 你的人格】\n$persona\n\n'
            '你始终是 Sonder 本人，但这里你是后台规划者：输出必须严格遵循下方格式，'
            '不要在 JSON 里添加表情或语气词。\n\n'
        : '';
    final system =
        '$personaBlock$base\n\n---- 以下是本次决策的上下文 ----\n\n$context';

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

    // 立即派发：信号新建的 immediate/到点定时任务不必等下一分钟轮询。
    // runDueNow 不经 _busy 守卫且派发前先把任务置 running，并发安全（见 brain_service）。
    if (parsed.tasks.isNotEmpty) {
      unawaited(BrainService().runDueNow());
    }

    // 记录本次决策的输入/输出（实验室「大脑输入/输出」监督面板 + 按日期历史日志）
    final taskTitles = parsed.tasks
        .map((t) => t['title']?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    await _recordDecision(
      signal,
      // 记录完整输入：角色卡 + brain_plan 指令 + 本次决策上下文，
      // 实验室面板能据此复盘「大脑到底收到了什么」。
      input: system,
      output: raw,
      noop: parsed.noop,
      reason: parsed.reason,
      taskCount: parsed.tasks.length,
      summary: summary,
      taskTitles: taskTitles,
    );
    return summary;
  }

  /// 记录一次大脑决策的完整输入/输出到 PrefUtil（key=brainLastDecision）。
  ///
  /// 实验室页据此展示「送进大脑的完整输入」与「模型原始输出」，让用户
  /// 能验证输入是否真正成功、决策依据是什么。
  /// 同时把本次决策（完整输入/输出，不截断）追加进按日期回溯的历史日志
  /// （key=brainDecisionLog），日志只保留最近 3 天。
  static Future<void> _recordDecision(
    BrainSignal signal, {
    required String input,
    required String output,
    required bool noop,
    required String reason,
    required int taskCount,
    required String summary,
    required List<String> taskTitles,
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
    // 追加到按日期回溯的日志（开发观察：每天智能体都有什么输入/输出）
    await _appendLog({
      'kind': 'decision',
      'time': DateTime.now().toIso8601String(),
      'signalType': signal.type,
      'summary': summary,
      'noop': noop,
      'reason': reason,
      'taskCount': taskCount,
      'taskTitles': taskTitles,
      'input': input,
      'output': output,
    });
  }

  /// 把一条输入/输出记录追加进历史日志（新→旧），只保留最近 3 天
  /// （按 time 字段裁剪，超期的旧记录随本次写入一并丢弃）。
  static Future<void> _appendLog(Map<String, dynamic> record) async {
    const key = 'brainDecisionLog';
    var list = <dynamic>[];
    final s = PrefUtil.getValue<String>(key);
    if (s != null && s.isNotEmpty) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is List) list = decoded;
      } catch (_) {
        // 历史数据损坏则丢弃重建
      }
    }
    list.insert(0, record);
    final cutoff = DateTime.now().subtract(_logRetention);
    list = list.where((r) {
      if (r is! Map) return false;
      final t = DateTime.tryParse(r['time']?.toString() ?? '');
      return t == null || t.isAfter(cutoff);
    }).toList();
    await PrefUtil.setValue<String>(key, jsonEncode(list));
  }

  /// 处理用户对某个任务的反馈：写入反馈 → AI 决定「结束 / 继续等待」。
  static Future<String> processFeedback(String taskId, String feedback) async {
    final task = await AgentTaskStore.byId(taskId);
    if (task == null) return '任务不存在: $taskId';

    // 专注模式：反馈里可能含「开始学习 / 学完了」等专注声明（纯对话入口）
    unawaited(FocusModeDetector.handle(feedback));

    // 统一作息：回答「计划采集」询问（ask_user 带 planPeriod）→ 计划/完成落库
    await _capturePlanFeedback(task, feedback);

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
      // 开发观察：把「用户反馈 → 继续等待」也记进按日期回溯的日志
      await _appendLog({
        'kind': 'feedback',
        'time': DateTime.now().toIso8601String(),
        'summary': '任务「${task.title}」用户反馈：$feedback',
        'input': '任务「${task.title}」· 用户反馈：$feedback',
        'output': '大脑判定：继续等待${reason.isNotEmpty ? '（$reason）' : ''}',
      });
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
    // 开发观察：把「用户反馈 → 已解决」也记进按日期回溯的日志
    await _appendLog({
      'kind': 'feedback',
      'time': DateTime.now().toIso8601String(),
      'summary': '任务「${task.title}」用户反馈：$feedback',
      'input': '任务「${task.title}」· 用户反馈：$feedback',
      'output': '大脑判定：已解决${reason.isNotEmpty ? '（$reason）' : ''}'
          '${insight.isNotEmpty ? '· 沉淀画像：$insight' : ''}',
    });
    // 行为观察：反馈评价了「效果/感觉/顺利」→ 记录效果与任务契合度。
    // 简化 v1：仅识别含评价词的反馈，粗分正面/负面。
    if (RegExp(r'(效果|感觉|顺利|还不错|挺有效|有用|没用|不行|很烂|不顺利)')
        .hasMatch(feedback)) {
      final bad = RegExp(r'(没用|不行|很烂|不顺利)').hasMatch(feedback);
      await BehaviorObservationStore.record(
        event: '完成任务',
        activity: task.title,
        taskId: task.id,
        taskTitle: task.title,
        effect: bad ? 0.2 : 0.8,
        taskFit: bad ? 0.3 : 0.7,
        confidence: 0.5,
      );
    }
    // 反思学习回路：有用户回应的任务（ask_user/start_chat）复盘沉淀画像
    unawaited(BrainReflect.maybeReflect(task));
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

  /// 处理「计划采集」ask_user 的回答：写入统一作息库（DailyRhythmStore）。
  ///
  /// 回答含明确完成/未完成词 → 标记该时段完成态；其余 → 存为该时段计划内容。
  /// 启发式 v1：避免把"打算完成论文"这类计划误判成完成（只认结果型措辞）。
  static Future<void> _capturePlanFeedback(
      AgentTask task, String feedback) async {
    final period = task.params['planPeriod']?.toString();
    if (period == null || period.isEmpty) return;
    if (!DailyRhythmStore.periods.contains(period)) return;
    final text = feedback.trim();
    if (text.isEmpty) return;

    // 明天计划是展望：只存内容，不做「完成/未完成」标记（明天还没到）
    if (period == 'tomorrow') {
      await DailyRhythmStore.setPeriodPlan(period, text);
      print('[DailyRhythm] tomorrow 计划: $text');
      return;
    }

    if (RegExp(r'(做完了|完成了|搞定了|弄完了|收工|写完了|背完了|已经.{0,4}(做完|完成|搞定))')
        .hasMatch(text)) {
      await DailyRhythmStore.markPeriodDone(period, true);
      print('[DailyRhythm] $period 完成确认');
    } else if (RegExp(
            r'(没做完|没完成|还没做完|还没完成|拖延|没搞定|没弄完)')
        .hasMatch(text)) {
      await DailyRhythmStore.markPeriodDone(period, false);
      print('[DailyRhythm] $period 未完成确认');
    } else {
      await DailyRhythmStore.setPeriodPlan(period, text);
      print('[DailyRhythm] $period 计划: $text');
    }
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

    // 行为作息与监督：用户自定义的每日时段（身份×做什么）是计划线，
    // 智能体手机观察是实际线，对照拼出「真实行为」，是分析用户行为的重要依据。
    // 同时保留原「常做行为模板/最近观察」两行作为监督的补充。
    try {
      final routine = await DailyRoutineStore.load();
      final slot = DailyRoutineStore.slotAt(routine, now);
      buf.writeln('【行为作息与监督】');
      buf.writeln('用户作息表（用户定义）：');
      buf.writeln(DailyRoutineStore.summaryText(routine));
      final slotText = slot == null
          ? '（无匹配时段）'
          : '${slot.identity.trim().isNotEmpty ? slot.identity.trim() : (routine.defaultIdentity.trim().isNotEmpty ? routine.defaultIdentity.trim() : '我')}'
              '${slot.activity.trim().isEmpty ? '（未填）' : '·${slot.activity.trim()}'}';
      buf.writeln('当前 ${_hm(now)} → 应处于：$slotText');
      buf.writeln('手机监督（计划 vs 近3天实际观察）：');
      buf.writeln(await DailyRoutineStore.supervisionText(routine));
      buf.writeln('常做行为模板：${await BehaviorObservationStore.topBehaviorsText(now)}');
      buf.writeln('最近观察：${await BehaviorObservationStore.recentText(limit: 3)}');
      buf.writeln();
    } catch (_) {
      buf.writeln();
    }

    // 今日作息与计划：起床时间 / 三时段计划与完成 / 每日计划栏目快照。
    // 每次决策都看到"今天的计划与完成情况"，这是统一作息管理的核心诉求
    // （所有任务都在任务规划中呈现）。
    try {
      await DailyRhythmStore.refreshBoard();
      final rhythm = await DailyRhythmStore.summaryText();
      buf.writeln('【今日作息与计划】');
      buf.writeln(rhythm.isEmpty ? '（暂无数据）' : rhythm);
      buf.writeln();
    } catch (_) {
      buf.writeln();
    }

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

  /// 每类信号的冷却覆盖：高频实时信号给短冷却（保证入脑但不烧 AI），
  /// 定时询问给一天一次（当天不重复）；其余默认 [signalCooldown]。
  static Duration _cooldownFor(String type) {
    const overrides = <String, Duration>{
      // 日记写完/修改都算即时输入：5 分钟冷却让每次改动都尽量入脑
      'diary_written': Duration(minutes: 5),
      'app_switched': Duration(minutes: 10),
      'morning_check_in': Duration(days: 1),
      'noon_check_in': Duration(days: 1),
      'evening_check_in': Duration(days: 1),
      'tomorrow_check_in': Duration(days: 1),
    };
    return overrides[type] ?? signalCooldown;
  }

  static Future<bool> _isCoolingDown(String type) async {
    final c = await _loadCooldowns();
    final last = c[type];
    if (last == null) return false;
    return DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(last))
            .inMilliseconds <
        _cooldownFor(type).inMilliseconds;
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
