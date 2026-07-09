import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/common/values/keyboard_state.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:refreshed/refreshed.dart';

import 'assistant_state.dart';

class AssistantLogic extends GetxController with WidgetsBindingObserver {
  final AssistantState state = AssistantState();

  late TextEditingController textEditingController = TextEditingController();
  late ScrollController scrollController = ScrollController();
  late FocusNode focusNode = FocusNode();

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

    // 添加用户消息
    state.messages.add(AIMessage(role: 'user', content: ask));
    update();
    toBottom();

    try {
      // 发起流式请求
      final stream = await _currentProvider!.chat(
        messages: state.messages
            .map((m) => AIMessage(role: m.role, content: m.content))
            .toList(),
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
    } catch (e) {
      final providerName = _currentProvider?.displayName ?? '未知';
      final url = state.currentProviderId.value;
      NoticeUtil.showToast('[$providerName] 请求失败，请检查:\n1. API 地址是否正确\n2. API Key 是否有效\n3. 模型名是否支持');
      print('[AI ERROR] Provider=$providerName URL=$url Error=$e');
      // 移除空白的助手消息
      if (state.messages.isNotEmpty &&
          state.messages.last.role == 'assistant' &&
          state.messages.last.content.isEmpty) {
        state.messages.removeLast();
        update();
      }
    }
  }

  void toBottom() {
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
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
