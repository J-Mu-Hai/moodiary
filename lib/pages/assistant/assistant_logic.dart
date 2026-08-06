import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/common/values/keyboard_state.dart';
import 'package:moodiary/pages/home/diary/diary_logic.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/ai_functions.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';
import 'package:moodiary/services/reply_chunker.dart';
import 'package:moodiary/utils/file_util.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:refreshed/refreshed.dart';

import 'assistant_state.dart';

class AssistantLogic extends GetxController with WidgetsBindingObserver {
  final AssistantState state = AssistantState();

  late TextEditingController textEditingController = TextEditingController();
  late ScrollController scrollController = ScrollController();
  late FocusNode focusNode = FocusNode();

  String? _systemPrompt; // AI 性格提示词（缓存）
  bool _systemInjected = false;

  bool _isGenerating = false; // 防并发发送
  int _session = 0; // newChat/切模型时自增，作废进行中的流

  List<double> heightList = [];

  /// 当前使用的 AI Provider
  AIProvider? _currentProvider;

  AIProvider? get currentProvider => _currentProvider;

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final height = MediaQuery.viewInsetsOf(Get.context!).bottom;
      if (heightList.isNotEmpty && height != heightList.last) {
        if (height > heightList.last &&
            state.keyboardState != KeyboardState.opening) {
          state.keyboardState = KeyboardState.opening;
        } else if (height < heightList.last &&
            state.keyboardState != KeyboardState.closing) {
          state.keyboardState = KeyboardState.closing;
          unFocus();
        }
      }
      if (heightList.isEmpty || height != heightList.last) {
        heightList.add(height);
      }
      if (height == 0 && state.keyboardState != KeyboardState.closed) {
        state.keyboardState = KeyboardState.closed;
        heightList.clear();
      }
    });
    super.didChangeMetrics();
  }

  @override
  void onReady() {
    WidgetsBinding.instance.addObserver(this);
    _loadProvider();
    super.onReady();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    textEditingController.dispose();
    scrollController.dispose();
    focusNode.dispose();
    super.onClose();
  }

  /// 从配置加载 AI Provider
  void _loadProvider() {
    final providersJson = PrefUtil.getValue<String>('aiProviders');
    if (providersJson == null || providersJson.isEmpty) {
      _currentProvider = null;
      return;
    }
    final list = jsonDecode(providersJson) as List;
    final configs = list.map((e) => AIProviderConfig.fromJson(e)).toList();
    if (configs.isEmpty) {
      _currentProvider = null;
      return;
    }

    // 读取上次选中的 Provider
    final currentId = PrefUtil.getValue<String>('aiCurrentProviderId') ?? '';
    AIProviderConfig? selectedConfig;
    if (configs.isNotEmpty) {
      if (currentId.isNotEmpty) {
        selectedConfig = configs.cast<AIProviderConfig?>().firstWhere(
            (c) => c!.id == currentId,
            orElse: () => null);
      }
      selectedConfig ??= configs.first;
    }

    if (selectedConfig == null) return;
    _currentProvider = AIProviderFactory.create(selectedConfig);
    state.currentProviderId.value = selectedConfig.id;
    state.currentModel.value = selectedConfig.model;
  }

  /// 切换 AI Provider
  Future<void> switchProvider(AIProviderConfig config) async {
    _currentProvider = AIProviderFactory.create(config);
    state.currentProviderId.value = config.id;
    state.currentModel.value = config.model;
    await PrefUtil.setValue<String>('aiCurrentProviderId', config.id);
    newChat();
  }

  /// 切换模型
  Future<void> switchModel(String model) async {
    state.currentModel.value = model;
    newChat();
  }

  /// 构建最近的日记摘要（用于 AI 上下文）
  Future<String?> _buildDiaryContext() async {
    try {
      // 获取最近 7 天的日记
      final now = DateTime.now();
      final recent = await IsarUtil.getDiariesByDateRange(
        now.subtract(const Duration(days: 7)),
        now,
      );
      if (recent.isEmpty) return null;

      final buf = StringBuffer('以下是用户最近的日记摘要，请据此回答：\n');
      for (final d in recent) {
        final date = '${d.time.month}/${d.time.day}';
        final mood = d.mood != null ? ' 心情${(d.mood! * 10).round()}/10' : '';
        final weather = d.weather.isNotEmpty ? ' ${d.weather.first}' : '';
        final title = d.title.isNotEmpty ? ' 《${d.title}》' : '';
        final snippet = d.contentText.length > 80
            ? d.contentText.substring(0, 80)
            : d.contentText;
        buf.writeln('[$date$weather$mood]$title');
        if (snippet.isNotEmpty) {
          buf.writeln('  > $snippet');
        }
      }
      buf.writeln('\n回答时结合这些日记内容给出有针对性的回应。');
      return buf.toString();
    } catch (e) {
      print('[AI Diary Error] $e');
      return null;
    }
  }

  /// 解析 AI 回复中的函数调用 [[CALL:函数名|参数JSON]]
  List<(String, Map<String, String>)> _extractFunctionCalls(String text) {
    final calls = <(String, Map<String, String>)>[];
    final regex = RegExp(r'\[\[CALL:(\w+)\|(.+?)\]\]');
    for (final match in regex.allMatches(text)) {
      final fnName = match.group(1)!;
      try {
        final rawArgs = match.group(2)!;
        final args = jsonDecode(rawArgs) as Map<String, dynamic>;
        calls.add((fnName, args.map((k, v) => MapEntry(k, v.toString()))));
      } catch (e) {
        print('[FunctionCall Parse Error] $fnName: $e');
      }
    }
    return calls;
  }

  /// 执行函数调用，并把结果返回给 AI 生成最终答案
  Future<void> _executeFunctionCalls(
      List<(String, Map<String, String>)> calls, String originalReply,
      {int depth = 0}) async {
    if (_currentProvider == null || depth >= 2) return; // 最多两跳，防死循环

    // 函数执行 + 二次生成期间亮打字指示器（AI"正在查数据"）
    state.isTyping.value = true;
    update();

    try {
      // 1. 执行所有函数
      final results = <String>[];
      for (final (fnName, args) in calls) {
        final result = await AiFunctionSystem.execute(fnName, args);
        results.add(result?.summary ?? '查询失败');
      }

      // 2. 追加函数结果
      final functionResultMsg = '函数调用结果：\n${results.join('\n')}\n\n请基于以上数据，自然、简洁地回应用户。';

      // 3. 从 state.messages 重建消息，去掉最后一个 user 之后的中间气泡
      var followUp = state.messages
          .map((m) => AIMessage(role: m.role, content: m.content))
          .toList();
      var lastUser = -1;
      for (var i = followUp.length - 1; i >= 0; i--) {
        if (followUp[i].role == 'user') {
          lastUser = i;
          break;
        }
      }
      while (followUp.length - 1 > lastUser) {
        followUp.removeLast();
      }

      // 4. 追加原始回复（含 CALL 的推理）+ 函数结果 + 追问
      followUp.add(AIMessage(role: 'assistant', content: originalReply));
      followUp.add(AIMessage(role: 'system', content: functionResultMsg));
      followUp.add(AIMessage(role: 'user', content: '请用刚才的查询结果，给出最终回答。'));
      followUp = _coalesceMessages(followUp);

      // 5. 二次调用补上人格与时间（system 不进 state，不补则人格/日期又丢失）
      if (_systemPrompt != null && _systemPrompt!.isNotEmpty) {
        followUp.insert(0, AIMessage(role: 'system', content: _systemPrompt!));
      }
      final sysCount = followUp.takeWhile((m) => m.role == 'system').length;
      followUp.insert(sysCount, _timeMessage());

      // 6. 二次流式回复，同样分块成气泡
      final followStream = await _currentProvider!.chat(
        messages: followUp,
        modelOverride: state.currentModel.value,
      );
      final chunker = await _streamAssistantReply(followStream);

      // 7. 二次回复里再出现 CALL → 递归处理
      final nested = _extractFunctionCalls(chunker.raw);
      if (nested.isNotEmpty) {
        await _executeFunctionCalls(nested, chunker.raw, depth: depth + 1);
      }
    } catch (e) {
      print('[FunctionCall Error] $e');
      state.isTyping.value = false;
      update();
    }
  }

  /// 当前时间消息：每次请求新鲜注入，杜绝 AI 日期幻觉
  AIMessage _timeMessage() {
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final wd = weekdays[now.weekday - 1];
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return AIMessage(
      role: 'system',
      content: '【当前时间】今天是 ${now.year}年${now.month}月${now.day}日 星期$wd，'
          '现在 $hh:$mm。回答涉及日期、时间、星期、时效性的问题时，一律以此刻为准，不要猜测或编造。',
    );
  }

  /// 出站消息合并：连续同角色消息合并成一条（兼容各 API + 省 token）
  List<AIMessage> _coalesceMessages(List<AIMessage> msgs) {
    final out = <AIMessage>[];
    for (final m in msgs) {
      if (out.isNotEmpty && out.last.role == m.role) {
        out[out.length - 1] = AIMessage(
            role: m.role, content: '${out.last.content}\n${m.content}');
      } else {
        out.add(m);
      }
    }
    return out;
  }

  /// 流式接收 AI 输出 → 增量分块成气泡 → 管理打字指示器。返回分块器（raw 供提取 CALL）。
  Future<ReplyChunker> _streamAssistantReply(Stream<String> stream) async {
    final mySession = _session;
    final chunker = ReplyChunker();
    var firstBubble = true;
    state.isTyping.value = true;
    update();
    WidgetsBinding.instance.addPostFrameCallback((_) => toBottom());

    try {
      await for (final chunk in stream) {
        if (_session != mySession) break; // newChat 已作废本次会话
        if (chunk.isEmpty) continue;
        for (final b in chunker.add(chunk)) {
          state.messages.add(AIMessage(role: 'assistant', content: b));
          if (firstBubble) {
            firstBubble = false;
            HapticFeedback.vibrate();
          }
          update();
          toBottom();
        }
      }
      if (_session == mySession) {
        for (final b in chunker.finish()) {
          state.messages.add(AIMessage(role: 'assistant', content: b));
          if (firstBubble) {
            firstBubble = false;
            HapticFeedback.vibrate();
          }
          update();
          toBottom();
        }
      }
    } finally {
      if (_session == mySession) {
        state.isTyping.value = false;
        update();
      }
    }
    return chunker;
  }

  /// 检测用户提问是否涉及日记内容，自动查询并注入
  Future<String?> _buildProactiveDiaryContext(String ask) async {
    // 触发条件：包含动作指令 + 时间或内容相关的词
    final actionKeywords = ['总结', '分析', '查看', '回顾', '整理', '调取', '调用', '检索', '查一下', '看看', '讲讲', '说说', '回顾'];
    final contentKeywords = ['日记', '记录', '内容', '心情', '任务', '计划', '复盘'];
    final timePatterns = [
      RegExp(r'(\d{1,2})月'), // 4月
      '这周', '上周', '这个月', '本月', '上个月', '最近', '今年',
    ];

    // 判断是否需要触发：动作指令 + (时间或日记内容词)
    final hasAction = actionKeywords.any((k) => ask.contains(k));
    final hasTime = timePatterns.any((t) => t is RegExp ? t.hasMatch(ask) : ask.contains(t));
    final hasContent = contentKeywords.any((k) => ask.contains(k));

    // 没有动作指令，或既没提时间也没提内容 → 不触发
    if (!hasAction || (!hasTime && !hasContent)) return null;

    // 尝试解析用户提到的时间范围
    DateTime start;
    DateTime end = DateTime.now();
    String periodLabel = '最近';
    int? targetYear;

    // 匹配年份（如 "2025年"）
    final yearMatch = RegExp(r'(20\d{2})年').firstMatch(ask);
    if (yearMatch != null) targetYear = int.parse(yearMatch.group(1)!);

    // 匹配 "X月" 模式
    final monthMatch = RegExp(r'(\d{1,2})月').firstMatch(ask);
    if (monthMatch != null) {
      final month = int.parse(monthMatch.group(1)!);
      final currentYear = DateTime.now().year;
      final year = targetYear ??
          (month > DateTime.now().month ? currentYear - 1 : currentYear);
      start = DateTime(year, month, 1);
      end = DateTime(year, month + 1, 0, 23, 59, 59);
      periodLabel = '$year年$month 月';
    } else if (ask.contains('今年')) {
      start = DateTime(DateTime.now().year, 1, 1);
      periodLabel = '今年';
    } else if (ask.contains('这周')) {
      start = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
      periodLabel = '本周';
    } else if (ask.contains('上周')) {
      start = DateTime.now().subtract(Duration(days: DateTime.now().weekday + 6));
      end = start.add(const Duration(days: 7));
      periodLabel = '上周';
    } else if (ask.contains('这个月') || ask.contains('本月')) {
      start = DateTime(DateTime.now().year, DateTime.now().month, 1);
      periodLabel = '这个月';
    } else {
      // 默认最近 14 天
      start = DateTime.now().subtract(const Duration(days: 14));
    }

    // 查询日记
    final result = await AiFunctionSystem.execute('getDiaryByDateRange', {
      'startDate': _fmtDate(start),
      'endDate': _fmtDate(end),
    });
    if (result == null) return null;

    // 判断是否提到具体分类（如"任务管理"）
    final knownCategories = ['任务管理', '每日计划', '觉醒时刻', '本周计划', '人物', '日记', '账本'];
    String? categoryName;
    for (final cat in knownCategories) {
      if (ask.contains(cat)) {
        categoryName = cat;
        break;
      }
    }

    String content;
    if (categoryName != null) {
      final catResult = await AiFunctionSystem.execute('getDiaryByCategory', {
        'categoryName': categoryName,
        'startDate': _fmtDate(start),
        'endDate': _fmtDate(end),
      });
      content = catResult?.summary ?? result.summary;
    } else {
      content = result.summary;
    }

    return '【系统已按你的指令检索到数据】$periodLabel 的相关记录：\n$content\n\n请基于这些真实数据回答，不要再说"我无法访问你的数据"。';
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void handleBack() {
    if (focusNode.hasFocus) {
      unFocus();
      Future.delayed(const Duration(seconds: 1), () {
        Get.back();
      });
    } else {
      Get.back();
    }
  }

  void unFocus() {
    focusNode.unfocus();
  }

  void newChat() {
    _session++; // 作废进行中的流
    state.messages.clear();
    state.isTyping.value = false;
    _systemInjected = false;
    update();
  }

  void clearText() {
    textEditingController.clear();
  }

  /// 发送对话请求
  Future<void> getAi(String ask) async {
    if (_currentProvider == null) {
      NoticeUtil.showToast('请先在实验室配置 AI 服务商');
      return;
    }
    if (!_currentProvider!.isConfigured) {
      NoticeUtil.showToast('当前 AI 服务商配置不完整');
      return;
    }
    if (_isGenerating) {
      NoticeUtil.showToast('正在生成中，请稍候');
      return;
    }
    _isGenerating = true;

    clearText();
    unFocus();

    try {
      // 先把用户消息加入界面显示
      state.messages.add(AIMessage(role: 'user', content: ask));
      state.isTyping.value = true; // 建连阶段就亮"正在输入"
      update();
      toBottom();

      // 构建发送给 AI 的消息列表（连续同角色合并）
      List<AIMessage> chatMessages = _coalesceMessages(state.messages
          .map((m) => AIMessage(role: m.role, content: m.content))
          .toList());

      // 注入 AI 性格系统提示词（每个对话只注入一次）
      if (!_systemInjected) {
        _systemPrompt ??= await AiPromptManager().buildSystemPrompt();
        if (_systemPrompt != null && _systemPrompt!.isNotEmpty) {
          chatMessages.insert(0, AIMessage(role: 'system', content: _systemPrompt!));
          _systemInjected = true;
        }
      }

      // 检测用户是否在询问日记相关的内容，自动注入数据
      try {
        final proactiveContext = await _buildProactiveDiaryContext(ask);
        if (proactiveContext != null) {
          chatMessages.insert(0, AIMessage(role: 'system', content: proactiveContext));
        }
      } catch (e) {
        print('[Proactive Diary Error] $e');
      }

      // 如果开启了日记读取，注入最近日记摘要
      if (state.diaryAccessEnabled.value) {
        try {
          final diaryContext = await _buildDiaryContext();
          if (diaryContext != null) {
            chatMessages.insert(0, AIMessage(role: 'system', content: diaryContext));
          }
        } catch (e) {
          print('[AI Diary Context Error] $e');
        }
      }

      // 时间注入：每次请求都新鲜注入，放在第一个非 system 消息之前（离用户问题最近）
      final sysCount = chatMessages.takeWhile((m) => m.role == 'system').length;
      chatMessages.insert(sysCount, _timeMessage());

      // 发起流式请求
      final stream = await _currentProvider!.chat(
        messages: chatMessages,
        modelOverride: state.currentModel.value,
      );

      // 接收流：增量分块成气泡（不再添加空占位消息）
      final chunker = await _streamAssistantReply(stream);

      // 处理 AI 的函数调用请求（[[CALL:函数名|参数JSON]]）
      final calls = _extractFunctionCalls(chunker.raw);
      if (calls.isNotEmpty) {
        await _executeFunctionCalls(calls, chunker.raw);
      }
    } catch (e, stack) {
      final providerName = _currentProvider?.displayName ?? '未知';
      // 写入日志文件
      try {
        final log = File(FileUtil.getErrorLogFilePath());
        await log.writeAsString(
          '[AI ERROR] $providerName | ${DateTime.now()}\n$e\n$stack\n---\n',
          mode: FileMode.append,
        );
      } catch (_) {}
      print('[AI ERROR] Provider=$providerName Error=$e\n$stack');
      NoticeUtil.showToast('请求失败，请检查 API 配置');
    } finally {
      _isGenerating = false;
    }
  }

  void toBottom() {
    if (scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  String getText() => textEditingController.text;

  Future<void> checkGetAi() async {
    final text = getText();
    if (text.isNotEmpty) {
      await getAi(text);
    } else {
      NoticeUtil.showToast('还没有输入问题');
    }
  }
}
