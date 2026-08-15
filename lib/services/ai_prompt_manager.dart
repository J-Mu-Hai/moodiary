import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 提示词管理器 — 从 assets 加载所有 prompt 和配置
class AiPromptManager {
  static final AiPromptManager _instance = AiPromptManager._();
  factory AiPromptManager() => _instance;
  AiPromptManager._();

  // 缓存已加载的提示词
  final Map<String, String> _cache = {};

  /// 加载提示词文件
  Future<String> loadPrompt(String name) async {
    if (_cache.containsKey(name)) return _cache[name]!;
    try {
      final content = await rootBundle.loadString('assets/ai/prompts/$name');
      _cache[name] = content;
      return content;
    } catch (e) {
      return '(提示词 $name 加载失败)';
    }
  }

  /// 加载 JSON 配置文件
  Future<dynamic> loadJson(String path) async {
    try {
      final content = await rootBundle.loadString('assets/ai/$path');
      return jsonDecode(content);
    } catch (e) {
      return null;
    }
  }

  /// 加载基础系统提示词
  Future<String> loadBaseSystemPrompt() async {
    return await loadPrompt('system_base.txt');
  }

  /// 加载私有知识库（认知档案）
  Future<String> loadKnowledgeBase() async {
    try {
      return await rootBundle.loadString('assets/ai/knowledge.md');
    } catch (e) {
      return '';
    }
  }

  /// 加载通用价值观概述（简短版，每次对话注入）
  Future<String> loadUniversalValuesOverview() async {
    try {
      return await rootBundle.loadString('assets/ai/values_overview.md');
    } catch (e) {
      return '';
    }
  }

  /// 加载触发器对应的提示词，并填充数据
  Future<String> buildTriggerPrompt(
      String triggerId, Map<String, String> data) async {
    final promptFile = {
      'daily_review': 'daily_review.txt',
      'weekly_review': 'weekly_review.txt',
      'idle_care': 'idle_chat.txt',
      'task_analysis': 'task_analyze.txt',
      'memory_consolidation': 'memory_consolidate.txt',
    }[triggerId];

    if (promptFile == null) return '';

    var prompt = await loadPrompt(promptFile);
    // 填充数据占位符
    for (final entry in data.entries) {
      prompt = prompt.replaceAll('{${entry.key}}', entry.value);
    }
    return prompt;
  }

  /// 构建完整的 System Prompt（基础性格 + 函数说明 + 触发器上下文）
  Future<String> buildSystemPrompt({
    String? triggerId,
    Map<String, String>? triggerData,
  }) async {
    final base = await loadBaseSystemPrompt();
    final personality = await loadJson('personality.json');
    final functions = await loadJson('functions.json');
    final knowledge = await loadKnowledgeBase();
    final valuesOverview = await loadUniversalValuesOverview();

    final buf = StringBuffer();
    buf.writeln(base);
    buf.writeln('\n---');

    // 通用价值观 · 概述（始终注入，三层结构之一）
    if (valuesOverview.isNotEmpty) {
      buf.writeln('\n【通用价值观 · 概述】');
      buf.writeln('这是长期的价值基线，任何对话默认遵循。遇到复杂价值判断、三观分歧时，可调用 getUniversalValues 获取对应主题的详细准则。');
      buf.writeln(valuesOverview);
    }

    // 私有知识库（认知档案）
    if (knowledge.isNotEmpty) {
      buf.writeln('\n【私有知识库 · 用户认知档案】');
      buf.writeln('分析任何事件前，优先阅读并调用以下关于用户的长期认知：');
      buf.writeln(knowledge);
    }

    // 性格设定
    if (personality is Map && personality.containsKey('speech_rules')) {
      buf.writeln('\n说话规则：');
      for (final rule in (personality['speech_rules'] as List)) {
        buf.writeln('- $rule');
      }
    }

    // 可用函数
    if (functions is List) {
      buf.writeln('\n---\n以下函数可以用来获取数据：');
      for (final fn in functions) {
        if (fn is Map) {
          final params = (fn['params'] as List?)?.map((p) {
            return '${p['name']}(${p['type']})';
          }).join(', ') ?? '';
          buf.writeln('- ${fn['name']}: ${fn['description']} [$params]');
        }
      }
      buf.writeln('需要获取数据时，用 [[CALL:函数名|参数JSON]] 格式。');
      // 示例日期动态生成，避免教模型错误的"当前"日期
      String fmtDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final today = DateTime.now();
      final weekAgo = today.subtract(const Duration(days: 7));
      buf.writeln('例如: [[CALL:getDiaryByDateRange|{"startDate":"${fmtDate(weekAgo)}","endDate":"${fmtDate(today)}"}]]');
    }

    // 触发器上下文
    if (triggerId != null && triggerData != null) {
      final triggerPrompt = await buildTriggerPrompt(triggerId, triggerData);
      if (triggerPrompt.isNotEmpty) {
        buf.writeln('\n---\n$triggerPrompt');
      }
    }

    return buf.toString();
  }
}
