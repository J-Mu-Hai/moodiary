import 'dart:async';
import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/common/models/isar/diary.dart';
import 'package:moodiary/pages/assistant/assistant_logic.dart';
import 'package:moodiary/pages/diary_details/diary_details_logic.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/router/app_routes.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/services/memory_service.dart';
import 'package:moodiary/utils/agent_channel.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:moodiary/utils/session_merger.dart';
import 'package:moodiary/utils/tts_speaker.dart';
import 'package:refreshed/refreshed.dart';

import 'agent_task.dart';
import 'behavior_observations.dart';
import 'daily_rhythm.dart';
import 'diary_ai_read.dart';

/// 智能体执行器 — 把任务按 action 分发到具体能力上。
///
/// 5 类能力：tts（语音提示）/ start_chat（发起会话）/ ask_user（提问等回应）/
/// block_screen（全屏阻断，有悬浮窗权限则系统级覆盖所有应用，否则回退 App 内）/
/// update_profile（沉淀画像）。
///
/// 执行后按动作类型写终态：一次性动作置 done；需要用户回应的置 waitingUser；
/// 阻断页置 running（由阻断页在结束/提前结束时写回反馈与终态）。
class AgentExecutor {
  static Future<void> execute(AgentTask task) async {
    print('[Executor] 执行任务「${task.title}」action=${task.action}');
    try {
      switch (task.action) {
        case 'tts':
          await _execTts(task);
          break;
        case 'start_chat':
          await _execStartChat(task, ask: false);
          break;
        case 'ask_user':
          await _execStartChat(task, ask: true);
          break;
        case 'block_screen':
          await _execBlockScreen(task);
          break;
        case 'update_profile':
          await _execUpdateProfile(task);
          break;
        case 'analyze_diaries':
          await _execAnalyzeDiaries(task);
          break;
        case 'open_diary':
          await _execOpenDiary(task);
          break;
        case 'nightly_review':
          await _execNightlyReview(task);
          break;
      }
      final after = await AgentTaskStore.byId(task.id);
      final last =
          after != null && after.feedback.isNotEmpty ? after.feedback.last : '';
      print('[Executor] 任务「${task.title}」终态=${after?.status} 反馈=$last');
      // 行为观察：任务闭环 → 记录「完成任务」（waitingUser 类任务等用户
      // 回复后由 processFeedback 收尾，这里只记一次到位为 done 的）。
      if (after != null && after.status == 'done') {
        unawaited(BehaviorObservationStore.record(
          event: '完成任务',
          activity: after.title,
          taskId: after.id,
          taskTitle: after.title,
          confidence: 0.6,
        ));
      }
    } catch (e) {
      print('[Executor] 任务「${task.title}」执行异常: $e');
      rethrow;
    }
  }

  static Future<void> _execTts(AgentTask task) async {
    final text = task.params['text']?.toString() ?? '';
    if (text.trim().isEmpty) {
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] 无朗读文本'];
      await AgentTaskStore.update(task);
      return;
    }
    final ok = await TtsSpeaker.speak(text);
    task.status = 'done';
    task.feedback = [
      ...task.feedback,
      ok ? '[执行] 已语音播报' : '[执行] 语音播报失败: ${TtsSpeaker.lastError}',
    ];
    await AgentTaskStore.update(task);
  }

  static Future<void> _execStartChat(AgentTask task,
      {required bool ask}) async {
    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] AI 未配置，跳过发起会话'];
      await AgentTaskStore.update(task);
      return;
    }

    final text = task.params['text']?.toString() ?? '';
    final question = task.params['question']?.toString() ?? '';
    final content = ask && question.isNotEmpty
        ? '（智能体需要你的配合）$question'
        : text;
    if (content.trim().isEmpty) {
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] 无会话内容'];
      await AgentTaskStore.update(task);
      return;
    }

    // 已有等待回应的会话时，不再重复发起（防大脑连发多个 start_chat 骚扰）
    final waiting = await AgentTaskStore.query(status: 'waitingUser');
    if (waiting.any((t) =>
        t.id != task.id &&
        (t.action == 'start_chat' || t.action == 'ask_user'))) {
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] 已有等待回应的会话，跳过重复发起'];
      await AgentTaskStore.update(task);
      return;
    }

    // ── 让「发起会话」真的抵达用户：语音提醒 → 回前台 → 切对话页 → 注入 ──
    // 之前只在助手页「未打开」时才走这套流程；助手页一旦开过（fenix 注册常驻
    // 栈中），后续任务全部变成静默注入，用户完全感知不到 → 已修复为每次执行。

    // 1. 语音提醒：仅当蓝牙耳机连接时播报开场白（耳机在 = 用户能私密听到，
    //    公开场合不会外放尴尬）；无耳机则跳过语音，直接切对话页。
    //    先播报再切页，让用户先「听见」这次主动接触。
    if (await AgentChannel.isBluetoothHeadset()) {
      final speech = ask && question.isNotEmpty ? question : text;
      await TtsSpeaker.speak(speech);
    }

    // 2. 把 App 带回前台（后台定时任务触发时唤起，Android 12+ 有 FGS 保活时可用）
    await AgentChannel.bringToFront();

    // 3. 切到助手页并注入开场白
    var injected = false;
    if (Get.currentRoute == AppRoutes.assistantPage) {
      // 用户此刻就在对话页：直接注入，不重复跳转
      try {
        final logic = Get.find<AssistantLogic>();
        logic.state.messages.add(AIMessage(role: 'assistant', content: content));
        logic.update();
        injected = true;
      } catch (e) {
        print('[Executor] 注入失败: $e');
      }
    }
    if (!injected) {
      // 未在对话页：跳转过去，页面建立后再注入开场白
      Get.toNamed(AppRoutes.assistantPage);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        if (Get.isRegistered<AssistantLogic>()) {
          final logic = Get.find<AssistantLogic>();
          logic.state.messages.add(
              AIMessage(role: 'assistant', content: content));
          logic.update();
          injected = true;
        }
      } catch (e) {
        print('[Executor] 跳转后注入失败: $e');
      }
    }

    task.status = 'waitingUser';
    task.feedback = [
      ...task.feedback,
      injected
          ? '[执行] 已发起会话，等待用户回应'
          : '[执行] 已跳转助手页但未注入内容',
    ];
    await AgentTaskStore.update(task);
  }

  static Future<void> _execBlockScreen(AgentTask task) async {
    // 已有进行中的阻断页时不重复开页（多任务并发时避免叠两个锁屏）
    final running =
        await AgentTaskStore.query(status: 'running', action: 'block_screen');
    if (running.any((t) => t.id != task.id)) {
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] 已有阻断页进行中，跳过重复开页'];
      await AgentTaskStore.update(task);
      return;
    }
    final duration = (task.params['durationMinutes'] as num?)?.toInt() ?? 15;
    // force 默认 true（强制锁屏：不可提前结束、拦截返回）；false 保留「提前结束」按钮
    final force = task.params['force'] as bool? ?? true;
    // 系统级悬浮窗：有权限则真·全屏锁屏（覆盖所有应用/拦截 Home 手势）；
    // 无权限则回退 App 内锁屏，并引导一次性授权
    final overlay = force && await AgentChannel.hasOverlayPermission();
    if (force && !overlay) {
      NoticeUtil.showToast('请授权「悬浮窗」权限以启用系统级强制锁屏');
      await AgentChannel.requestOverlayPermission();
    }
    Get.toNamed(AppRoutes.blockScreenPage, arguments: {
      'taskId': task.id,
      'title': task.params['title']?.toString() ?? task.title,
      'reason': task.params['reason']?.toString() ?? '',
      'durationMinutes': duration,
      'force': force,
      'overlay': overlay,
    });
    // 阻断页在结束/提前结束时写回反馈与终态；此处置 running 表示进行中
    task.status = 'running';
    task.feedback = [
      ...task.feedback,
      '[执行] 已打开阻断页（$duration 分钟${force ? '，强制' : ''}）',
    ];
    await AgentTaskStore.update(task);
  }

  static Future<void> _execUpdateProfile(AgentTask task) async {
    final summary = await MemoryService.consolidate();
    task.status = 'done';
    task.feedback = [...task.feedback, '[执行] 画像沉淀：$summary'];
    await AgentTaskStore.update(task);
  }

  /// 定位并打开一篇指定日记（智能体「控制软件进入某个日记」能力）。
  ///
  /// params：date=yyyy-M-d 按天查；query=标题/内容关键词（支持"今天/昨天"归一化）；
  /// 都不给则打开最近一篇。找到后先把 App 带回前台，再按 map_logic 的导航模式
  /// （Bind.lazyPut tag=diary.id + Get.toNamed diaryPage）进入日记页。
  static Future<void> _execOpenDiary(AgentTask task) async {
    final diary = await _resolveDiary(task.params);
    if (diary == null) {
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] 未找到匹配日记'];
      await AgentTaskStore.update(task);
      return;
    }

    final title = diary.title.isEmpty ? '(无标题)' : diary.title;
    try {
      await AgentChannel.bringToFront();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      Bind.lazyPut(() => DiaryDetailsLogic(), tag: diary.id);
      // 不 await 路由：任务应立即完成，等用户看完关页会阻塞后续派发
      unawaited(Get.toNamed(
        AppRoutes.diaryPage,
        arguments: [diary.clone(), false],
      ));
    } catch (e) {
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] 打开日记失败: $e'];
      await AgentTaskStore.update(task);
      return;
    }

    task.status = 'done';
    task.feedback = [...task.feedback, '[执行] 已打开日记《$title》'];
    await AgentTaskStore.update(task);
  }

  /// 按 params 解析目标日记：date → 当天第一篇；query（含今天/昨天归一化）→
  /// 关键词搜索第一条；都没有 → 最近一篇。
  static Future<Diary?> _resolveDiary(Map<String, dynamic> params) async {
    final now = DateTime.now();

    final dateStr = params['date']?.toString().trim() ?? '';
    if (dateStr.isNotEmpty) {
      final dt = DateTime.tryParse(dateStr);
      if (dt != null) {
        final day = await IsarUtil.getDiaryByDay(dt);
        if (day.isNotEmpty) return day.first;
      }
    }

    final query = params['query']?.toString().trim() ?? '';
    if (query.isNotEmpty) {
      if (query == '今天' || query == '今日') {
        final day = await IsarUtil.getDiaryByDay(now);
        if (day.isNotEmpty) return day.first;
      } else if (query == '昨天' || query == '昨日') {
        final day = await IsarUtil.getDiaryByDay(
            now.subtract(const Duration(days: 1)));
        if (day.isNotEmpty) return day.first;
      } else {
        final hits = await IsarUtil.searchDiaries(query);
        if (hits.isNotEmpty) return hits.first;
      }
    }

    final all = await IsarUtil.getAllDiariesSorted();
    if (all.isNotEmpty) return all.first;
    return null;
  }

  /// 读取分析未读日记：能写画像的直接沉淀，想聊的建晚些的聊天任务，
  /// 最后全部标记已读。
  static Future<void> _execAnalyzeDiaries(AgentTask task) async {
    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      // 无法分析：标记已读并结束，避免该任务反复重试
      final unread = await DiaryAiReadStore.unreadDiaries(limit: 10);
      await DiaryAiReadStore.markReadAll(unread, note: 'AI 未配置，跳过分析');
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] AI 未配置，已跳过并标记已读'];
      await AgentTaskStore.update(task);
      return;
    }

    final diaries = await DiaryAiReadStore.unreadDiaries(limit: 10);
    if (diaries.isEmpty) {
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] 没有未读日记'];
      await AgentTaskStore.update(task);
      return;
    }

    // 组装素材：时间 + 标题 + 心情 + 截断正文
    final buf = StringBuffer();
    String fmtHM(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    for (final d in diaries) {
      final mood = ' 心情${(d.mood * 10).round()}/10';
      final title = d.title.isNotEmpty ? '《${d.title}》' : '(无标题)';
      final content = d.contentText.length > 300
          ? '${d.contentText.substring(0, 300)}…'
          : d.contentText;
      buf.writeln('--- ${fmtHM(d.time)} $title$mood ---');
      if (content.isNotEmpty) buf.writeln(content);
      buf.writeln();
    }

    final prompt = '''
你是 Moodsonder 智能体。请阅读下面的用户日记，判断：
1. 有哪些值得沉淀进用户画像的事实/认知（姓名/年龄/身份/作息/梦想/行为逻辑/偏好等）→ profile
2. 哪些地方你很想和用户聊聊（关怀、追问、建议）→ chat（一句话自然的开场白）
只输出严格 JSON（不要其他内容）：
{"profile":["[类别] 要点1","[类别] 要点2"],"chat":[{"message":"一句自然的开场白"}]}
- 类别只能从：[基础认知][生活习惯][情绪状态][偏好与习惯][目标与痛点][人际关系][行为规律][梦想与理想][行为逻辑] 中选择
- 把握不准的事实不要写进 profile；没有想聊的则 chat 为空数组
- profile 每条 20-40 字，具体不空泛

以下是日记：
$buf''';

    try {
      final stream = await provider.chat(messages: [
        AIMessage(role: 'user', content: prompt),
      ]);
      final sb = StringBuffer();
      await for (final chunk in stream) {
        sb.write(chunk);
      }
      final raw = sb.toString().trim();
      if (raw.isEmpty) throw Exception('模型未返回内容');

      final (profile, chat) = _parseAnalyze(raw);

      final fb = StringBuffer('[执行] 已读 ${diaries.length} 篇日记');
      if (profile.isNotEmpty) {
        await MemoryService.mergeAspects(profile);
        fb.write('，沉淀画像 ${profile.length} 条');
      }
      if (chat.isNotEmpty) {
        // 建聊天任务：定在约 2 小时后，让用户抽空对话，不即时打断
        final first = chat.first;
        await AgentTaskStore.add(AgentTask(
          title: '和用户聊聊日记里的内容',
          kind: 'scheduled',
          action: 'start_chat',
          params: {'text': first},
          scheduledAt: DateTime.now().add(const Duration(hours: 2)),
          priority: 1,
        ));
        fb.write('，约 2 小时后想和你聊聊：$first');
      }
      await DiaryAiReadStore.markReadAll(diaries,
          note: profile.take(2).join('；'));

      task.status = 'done';
      task.feedback = [...task.feedback, fb.toString()];
      await AgentTaskStore.update(task);
    } catch (e) {
      // AI 调用失败：不标记已读，留给下次 diary_stable 重试（避免丢数据）；
      // 任务本身置 done，避免执行器反复重试同一任务。
      print('[Executor] analyze_diaries 调用失败: $e');
      task.status = 'done';
      task.feedback = [...task.feedback, '[执行] 分析失败（未标记已读，可重试）: $e'];
      await AgentTaskStore.update(task);
    }
  }

  /// 晚间复盘：梳理今天。
  ///
  /// 确定性每日例行（不经大脑规划），由 BrainService 每天 23:00 后创建：
  /// 读当天未读日记 + 使用时间线 + 今日作息与计划 + 用户任务板块 →
  /// AI 产出画像增量 + 温柔复盘；没收集到的计划空缺并入复盘内容。
  /// 沉淀画像、标记日记已读、把复盘存为「待读」，用户下次打开助手页时看到。
  /// 不跳页不语音：复盘是安静动作，复盘内容在用户主动打开对话时才呈现。
  static Future<void> _execNightlyReview(AgentTask task) async {
    final provider = AiProviderManager().currentProvider;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final dateLabel = '${day.month}月${day.day}日';

    if (provider == null || !provider.isConfigured) {
      // AI 未配置：不标记已读（日记留给以后分析），只安静结束任务
      task.status = 'done';
      task.feedback = [...task.feedback, '[归位] AI 未配置，跳过归位（未读日记保留）'];
      await AgentTaskStore.update(task);
      return;
    }

    // 1. 收集素材（纯本地数据，不打扰）
    final unread = await _unreadDiariesForDay(day);
    final timeline = await _usageTimelineText(day);
    final pendingTasks = await _pendingTaskText();
    final profile = await MemoryService.getProfile();

    // 2. 组装提示词（角色卡保证是温晚照本人在复盘）
    final base = await AiPromptManager().loadPrompt('nightly_review.txt');
    final persona = await AiPromptManager().loadPersona();
    final system = [
      if (persona.isNotEmpty) '【角色卡】\n$persona',
      base,
    ].join('\n\n');

    final material = StringBuffer()..writeln('【归位日期】$dateLabel');
    if (unread.isEmpty) {
      material.writeln('\n【当天的日记】这天没有写日记。');
    } else {
      material.writeln('\n【当天的日记】');
      String fmtHM(DateTime t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      for (final d in unread) {
        final mood = ' 心情${(d.mood * 10).round()}/10';
        final title = d.title.isNotEmpty ? '《${d.title}》' : '(无标题)';
        final content = d.contentText.length > 300
            ? '${d.contentText.substring(0, 300)}…'
            : d.contentText;
        material.writeln('--- ${fmtHM(d.time)} $title$mood ---');
        if (content.isNotEmpty) material.writeln(content);
        material.writeln();
      }
    }
    // 统一作息：读今日作息库（起床/分时段计划/完成情况），空缺并入复盘
    await DailyRhythmStore.refreshBoard();
    final rhythm = await DailyRhythmStore.summaryText();

    material
      ..writeln('\n【当天的使用时间线】（手机使用记录，用于推断作息与行为逻辑）')
      ..writeln(timeline.isEmpty ? '（无使用记录）' : timeline)
      ..writeln('\n【今日作息与计划】（起床时间/各时段计划与完成/每日计划栏目；'
          '未收集的时段会标"（未收集）"，复盘时自然带出空缺）')
      ..writeln(rhythm.isEmpty ? '（暂无数据）' : rhythm)
      ..writeln('\n【用户任务板块（未完成）】')
      ..writeln(pendingTasks.isEmpty ? '（无未完成任务）' : pendingTasks)
      ..writeln('\n【当前画像】（已有认知，新的不要重复）')
      ..writeln(profile.isEmpty ? '（暂无）' : profile);

    // 3. 调用模型
    final stream = await provider.chat(messages: [
      AIMessage(role: 'system', content: system),
      AIMessage(role: 'user', content: material.toString()),
    ]);
    final sb = StringBuffer();
    await for (final chunk in stream) {
      sb.write(chunk);
    }
    final raw = sb.toString().trim();
    if (raw.isEmpty) throw Exception('模型未返回内容');

    final (profileAdds, review) = _parseNightlyReview(raw);

    // 4. 落地：沉淀画像 → 标记已读 → 存复盘待读
    final fb = StringBuffer('[归位] 已梳理 $dateLabel');
    if (profileAdds.isNotEmpty) {
      await MemoryService.mergeAspects(profileAdds, source: 'diary_analysis');
      fb.write('，沉淀画像 ${profileAdds.length} 条');
    }
    await DiaryAiReadStore.markReadAll(unread,
        note: profileAdds.take(2).join('；'));
    if (review.isNotEmpty) {
      await _storeNightReview(day, review);
      fb.write('，留下当晚复盘');
    }
    task.status = 'done';
    task.feedback = [...task.feedback, fb.toString()];
    await AgentTaskStore.update(task);
  }

  /// 把当晚复盘存为「待读」，用户下次打开助手页时注入。
  static Future<void> _storeNightReview(DateTime day, String content) async {
    await PrefUtil.setValue<String>(
      'nightlyReview',
      jsonEncode({
        'date': '${day.year}-${day.month}-${day.day}',
        'content': content,
      }),
    );
  }

  /// 某一天的未读日记（正序还原一天经过）。
  static Future<List<Diary>> _unreadDiariesForDay(DateTime day) async {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd =
        dayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));
    final all = await IsarUtil.getDiariesByDateRange(dayStart, dayEnd);
    final read = await DiaryAiReadStore.load();
    return all.where((d) => d.show && !read.containsKey(d.id)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  /// 一天的使用时间线文本（合并相邻碎片，供归位推断作息与行为逻辑）。
  static Future<String> _usageTimelineText(DateTime day) async {
    try {
      final sessions = await IsarUtil.getUsageSessionsByDay(
          '${day.year}/${day.month}/${day.day}');
      if (sessions.isEmpty) return '';
      String fmtHM(DateTime t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      String fmtDur(int ms) {
        final m = (ms / 60000).round();
        if (m < 1) return '<1分钟';
        return m < 60 ? '$m分钟' : '${m ~/ 60}小时${m % 60}分钟';
      }

      final buf = StringBuffer();
      for (final s in mergeAdjacentSessions(sessions)) {
        final end = s.isOpen ? '现在' : fmtHM(s.end!);
        final app = s.appName.isEmpty ? s.packageName : s.appName;
        buf.writeln('- ${fmtHM(s.start)}~$end $app（${fmtDur(s.durationMs)}）');
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  /// 用户「任务管理」分类下未完成的任务文本。
  static Future<String> _pendingTaskText() async {
    try {
      final cats = await IsarUtil.getAllCategoryAsync();
      final taskCat =
          cats.where((c) => c.categoryName == '任务管理').toList();
      if (taskCat.isEmpty) return '';
      final cat = taskCat.first;
      final now = DateTime.now();
      final all = await IsarUtil.getDiariesByDateRange(
          now.subtract(const Duration(days: 30)), now);
      final pending = all
          .where((d) =>
              d.show && d.categoryId == cat.id && !d.tags.contains('完成'))
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      if (pending.isEmpty) return '';
      final buf = StringBuffer();
      for (final d in pending.take(20)) {
        final title = d.title.isNotEmpty ? d.title : '(无标题)';
        buf.writeln('- $title（${d.time.month}月${d.time.day}日）');
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  /// 解析归位输出：`{"profile":["[类别] 要点"],"review":"温柔复盘"}`。
  static (List<String>, String) _parseNightlyReview(String raw) {
    final profile = <String>[];
    String text = raw.trim();
    text = text.replaceFirst(RegExp(r'^```(json)?\s*'), '').trim();
    text = text.replaceFirst(RegExp(r'\s*```$'), '').trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final m = jsonDecode(text.substring(start, end + 1)) as Map;
        if (m['profile'] is List) {
          profile.addAll((m['profile'] as List).whereType<String>());
        }
        return (profile, m['review']?.toString().trim() ?? '');
      } catch (_) {
        // fallthrough → 整个文本视为复盘，不丢内容
      }
    }
    return (profile, text);
  }

  /// 解析 analyze_diaries 输出，宽容处理 ```json 围栏与前后杂文。
  static (List<String>, List<String>) _parseAnalyze(String raw) {
    final profile = <String>[];
    final chat = <String>[];
    String text = raw.trim();
    text = text.replaceFirst(RegExp(r'^```(json)?\s*'), '').trim();
    text = text.replaceFirst(RegExp(r'\s*```$'), '').trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final m = jsonDecode(text.substring(start, end + 1)) as Map;
        if (m['profile'] is List) {
          profile.addAll((m['profile'] as List).whereType<String>());
        }
        if (m['chat'] is List) {
          for (final c in (m['chat'] as List)) {
            if (c is Map && c['message'] != null) {
              chat.add(c['message'].toString());
            } else if (c is String) {
              chat.add(c);
            }
          }
        }
        return (profile, chat);
      } catch (_) {
        // fallthrough → 退化按行提取
      }
    }
    final lineRe = RegExp(r'^\[[^\]]+\].+');
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (lineRe.hasMatch(l)) profile.add(l);
    }
    return (profile, chat);
  }
}
