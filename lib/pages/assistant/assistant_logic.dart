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
      List<(String, Map<String, String>)> calls, String originalReply) async {
    if (_currentProvider == null) return;

    try {
      // 1. 执行所有函数
      final results = <String>[];
      for (final (fnName, args) in calls) {
        final result = await AiFunctionSystem.execute(fnName, args);
        results.add(result?.summary ?? '查询失败');
      }

      // 2. 更新用户消息，追加函数结果
      final functionResultMsg = '函数调用结果：\n${results.join('\n')}\n\n请基于以上数据，自然、简洁地回应用户。';

      // 3. 重新调用 AI（带上原始回复 + 函数结果）
      final followUpMessages = state.messages
          .map((m) => AIMessage(role: m.role, content: m.content))
          .toList();

      // 把原始回复（含 CALL）替换为函数结果
      if (followUpMessages.isNotEmpty &&
          followUpMessages.last.role == 'assistant') {
        followUpMessages[followUpMessages.length - 1] =
            AIMessage(role: 'assistant', content: originalReply);
        followUpMessages.add(AIMessage(role: 'system', content: functionResultMsg));
        followUpMessages.add(AIMessage(role: 'user', content: '请用刚才的查询结果，给出最终回答。'));
      }

      final followStream = await _currentProvider!.chat(
        messages: followUpMessages,
        modelOverride: state.currentModel.value,
      );

      // 4. 展示最终回答
      final finalContent = StringBuffer();
      await for (final chunk in followStream) {
        if (chunk.isNotEmpty) {
          finalContent.write(chunk);
          if (state.messages.isNotEmpty) {
            state.messages[state.messages.length - 1] =
                AIMessage(role: 'assistant', content: finalContent.toString());
            update();
            toBottom();
          }
        }
      }
    } catch (e) {
      print('[FunctionCall Error] $e');
    }
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
    state.messages.clear();
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

    clearText();
    unFocus();

    try {
      // 先把用户消息加入界面显示
      state.messages.add(AIMessage(role: 'user', content: ask));
      update();
      toBottom();

      // 构建发送给 AI 的消息列表
      List<AIMessage> chatMessages = state.messages
          .map((m) => AIMessage(role: m.role, content: m.content))
          .toList();

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

      // 发起流式请求
      final stream = await _currentProvider!.chat(
        messages: chatMessages,
        modelOverride: state.currentModel.value,
      );

      // 添加空助手消息占位
      final replyMsg = AIMessage(role: 'assistant', content: '');
      state.messages.add(replyMsg);
      update();

      // 接收流
      final replyContent = StringBuffer();
      await for (final chunk in stream) {
        if (chunk.isNotEmpty) {
          replyContent.write(chunk);
          final last = state.messages.last;
          if (last.role == 'assistant') {
            state.messages[state.messages.length - 1] =
                AIMessage(role: 'assistant', content: replyContent.toString());
            HapticFeedback.vibrate();
            update();
            toBottom();
          }
        }
      }

      // 处理 AI 的函数调用请求（[[CALL:函数名|参数JSON]]）
      final calls = _extractFunctionCalls(replyContent.toString());
      if (calls.isNotEmpty) {
        await _executeFunctionCalls(calls, replyContent.toString());
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
      // 如果用户消息已经添加（首次失败时还没添加）
      if (state.messages.isNotEmpty &&
          state.messages.last.role == 'assistant' &&
          state.messages.last.content.isEmpty) {
        state.messages.removeLast();
        update();
      }
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
