import 'dart:async';
import 'dart:convert';

import 'package:moodiary/services/ai_functions.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';
import 'package:moodiary/services/output_splitter.dart';

/// 触发器优先级
enum TriggerPriority { urgent, normal, gentle }

/// 触发器定义
class TriggerDef {
  final String id;
  final String name;
  final String description;
  final int cooldownHours;
  final TriggerPriority priority;
  final List<String> requiredData;
  final String promptFile;

  TriggerDef({
    required this.id,
    required this.name,
    required this.description,
    required this.cooldownHours,
    required this.priority,
    required this.requiredData,
    required this.promptFile,
  });

  factory TriggerDef.fromJson(Map<String, dynamic> json) => TriggerDef(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        cooldownHours: json['cooldownHours'] as int? ?? 6,
        priority: _parsePriority(json['priority'] as String? ?? 'normal'),
        requiredData: (json['requiredData'] as List?)?.cast<String>() ?? [],
        promptFile: json['promptFile'] as String? ?? '',
      );

  static TriggerPriority _parsePriority(String p) {
    switch (p) {
      case 'urgent':
        return TriggerPriority.urgent;
      case 'gentle':
        return TriggerPriority.gentle;
      default:
        return TriggerPriority.normal;
    }
  }
}

/// 触发器执行结果
class TriggerResult {
  final String triggerId;
  final List<String> messages;
  final DateTime triggeredAt;

  TriggerResult({
    required this.triggerId,
    required this.messages,
    required this.triggeredAt,
  });
}

/// 触发器引擎
class TriggerEngine {
  final AiPromptManager _promptManager = AiPromptManager();
  final List<TriggerDef> _triggers = [];
  final Map<String, DateTime> _cooldowns = {};
  Timer? _scheduler;

  /// 从配置文件加载触发器（带内置后备）
  Future<void> loadTriggers() async {
    _triggers.clear();
    try {
      final json = await _promptManager.loadJson('triggers.json') as List;
      if (json.isNotEmpty) {
        for (final item in json) {
          _triggers.add(TriggerDef.fromJson(item));
        }
        return;
      }
    } catch (_) {}
    // 后备：使用内置触发器
    _triggers.addAll(_builtinTriggers);
  }

  static List<TriggerDef> get _builtinTriggers => [
        TriggerDef(
          id: 'daily_review',
          name: '每日复盘',
          description: '每晚 22:00 检查今日计划和执行情况',
          cooldownHours: 23,
          priority: TriggerPriority.normal,
          requiredData: ['getTodayPlan', 'getDiaryByDateRange'],
          promptFile: 'daily_review.txt',
        ),
        TriggerDef(
          id: 'weekly_review',
          name: '周报',
          description: '每周日 21:00 总结本周',
          cooldownHours: 160,
          priority: TriggerPriority.normal,
          requiredData: ['getDiaryByDateRange', 'getTaskAnalysis', 'getDiaryByCategory'],
          promptFile: 'weekly_review.txt',
        ),
        TriggerDef(
          id: 'idle_care',
          name: '闲置关怀',
          description: '用户闲置 2 分钟时问候',
          cooldownHours: 4,
          priority: TriggerPriority.gentle,
          requiredData: ['getDiaryByDateRange'],
          promptFile: 'idle_chat.txt',
        ),
      ];

  static String _userMessageForTrigger(String triggerId) {
    switch (triggerId) {
      case 'idle_care':
        return '随便聊两句，自然一点，像朋友打招呼。';
      case 'daily_review':
        return '帮我回顾一下今天。';
      case 'weekly_review':
        return '帮我总结一下这周。';
      default:
        return '和用户聊聊天。';
    }
  }

  /// 获取所有触发器
  List<TriggerDef> get triggers => List.unmodifiable(_triggers);

  /// 检查冷却
  bool isCooling(String triggerId, {int? overrideHours}) {
    final last = _cooldowns[triggerId];
    if (last == null) return false;
    final trigger = _triggers.where((t) => t.id == triggerId).firstOrNull;
    final hours = overrideHours ?? trigger?.cooldownHours ?? 6;
    return DateTime.now().difference(last).inHours < hours;
  }

  /// 触发并执行一个触发器
  Future<TriggerResult?> fire(String triggerId,
      {Map<String, String>? extraData}) async {
    if (isCooling(triggerId)) return null;
    final trigger = _triggers.where((t) => t.id == triggerId).firstOrNull;
    if (trigger == null) return null;

    // 1. 收集数据
    final data = <String, String>{};
    for (final fnName in trigger.requiredData) {
      final result = await AiFunctionSystem.execute(fnName, {});
      if (result != null) {
        data[fnName] = result.summary;
        data['${fnName}_raw'] = jsonEncode(result.data);
      }
    }
    if (extraData != null) data.addAll(extraData);

    // 2. 构建 system prompt
    final systemPrompt = await _promptManager.buildSystemPrompt(
      triggerId: triggerId,
      triggerData: data,
    );

    // 3. 调用 AI 生成（通过回调执行，由外部注入 provider）
    if (onGenerate == null) return null;

    // 根据触发器类型生成不同的用户提示
    final userMsg = _userMessageForTrigger(triggerId);
    final fullContent = await onGenerate!(systemPrompt, userMsg);
    if (fullContent == null || fullContent.isEmpty) return null;

    // 4. 拆句
    final sentences = OutputSplitter.split(fullContent);

    // 5. 记录冷却
    _cooldowns[triggerId] = DateTime.now();

    return TriggerResult(
      triggerId: triggerId,
      messages: sentences,
      triggeredAt: DateTime.now(),
    );
  }

  /// AI 生成回调（由外部注入）
  Future<String?> Function(String systemPrompt, String userMessage)? onGenerate;
}
