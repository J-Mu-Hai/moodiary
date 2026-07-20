import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/common/values/keyboard_state.dart';
import 'package:moodiary/pages/home/diary/diary_logic.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
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
      await for (final chunk in stream) {
        if (chunk.isNotEmpty) {
          final last = state.messages.last;
          if (last.role == 'assistant') {
            state.messages[state.messages.length - 1] =
                AIMessage(role: 'assistant', content: last.content + chunk);
            HapticFeedback.vibrate();
            update();
            toBottom();
          }
        }
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
