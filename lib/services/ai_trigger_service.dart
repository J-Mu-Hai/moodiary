import 'dart:async';

import 'package:moodiary/pages/assistant/assistant_logic.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/services/ai_triggers.dart';
import 'package:refreshed/refreshed.dart';

/// AI 触发器服务 — 管理所有定时和事件触发器
class AiTriggerService {
  static final AiTriggerService _instance = AiTriggerService._();
  factory AiTriggerService() => _instance;
  AiTriggerService._();

  final TriggerEngine _engine = TriggerEngine();
  Timer? _timer;
  DateTime _lastActivity = DateTime.now();
  bool _initialized = false;

  /// 初始化：加载触发器配置 + 启动定时检查
  Future<void> init() async {
    if (_initialized) return;
    await _engine.loadTriggers();
    _engine.onGenerate = _onAiGenerate;
    _startTimer();
    _initialized = true;
    print('[TriggerService] 已初始化，${_engine.triggers.length} 个触发器');
  }

  /// 用户活跃时调用（刷新闲置计时）
  void notifyActivity() {
    _lastActivity = DateTime.now();
  }

  /// 用户写完日记时调用
  Future<void> notifyDiaryWritten() async {
    // 可触发 task_analysis 等事件类触发器
    // await _engine.fire('task_analysis');
  }

  /// 定时检查（每分钟）
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  /// 检查所有触发器
  Future<void> _check() async {
    final now = DateTime.now();

    for (final trigger in _engine.triggers) {
      // 检查时间触发器
      if (trigger.id == 'daily_review' && now.hour == 22 && now.minute == 0) {
        await _fireAndShow(trigger.id);
      }
      if (trigger.id == 'weekly_review' &&
          now.weekday == DateTime.sunday &&
          now.hour == 21 &&
          now.minute == 0) {
        await _fireAndShow(trigger.id);
      }
      // 画像沉淀：深夜 23:30 后台执行（静默，不注入对话）
      if (trigger.id == 'memory_consolidation' &&
          now.hour == 23 &&
          now.minute == 30) {
        await _fireAndShow(trigger.id);
      }
    }

    // 闲置检查
    if (_engine.triggers.any((t) => t.id == 'idle_care')) {
      final idleMinutes = DateTime.now().difference(_lastActivity).inMinutes;
      if (idleMinutes >= 2 && !_engine.isCooling('idle_care')) {
        await _fireAndShow('idle_care');
      }
    }
  }

  /// 触发执行并推送到界面
  Future<void> _fireAndShow(String triggerId) async {
    final result = await _engine.fire(triggerId);
    if (result == null || result.messages.isEmpty) return;

    try {
      // 找到助手页面 logic，把消息注入对话
      if (Get.isRegistered<AssistantLogic>()) {
        final logic = Get.find<AssistantLogic>();
        for (final msg in result.messages) {
          logic.state.messages.add(AIMessage(role: 'assistant', content: msg));
        }
        logic.update();
      }
    } catch (e) {
      print('[TriggerService] 推送失败: $e');
    }
  }

  /// AI 生成回调
  Future<String?> _onAiGenerate(String systemPrompt, String userMessage) async {
    // 从 ProviderManager 获取当前 AI Provider 并调用
    try {
      final pm = AiProviderManager();
      final provider = pm.currentProvider;
      if (provider == null) return 'AI 未配置';

      final stream = await provider.chat(
        messages: [
          AIMessage(role: 'system', content: systemPrompt),
          AIMessage(role: 'user', content: userMessage),
        ],
      );

      String result = '';
      await for (final chunk in stream) {
        result += chunk;
      }
      return result;
    } catch (e) {
      print('[TriggerService] AI 生成失败: $e');
      return null;
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
