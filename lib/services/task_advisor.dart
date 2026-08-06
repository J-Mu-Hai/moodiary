import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/common/models/task_plan.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';
import 'package:moodiary/services/task_doc_parser.dart';

/// 任务规划 AI 顾问 — 生成结构化建议卡片 + 一键应用。
///
/// 复用现有 AI 链路：`AiProviderManager().currentProvider` +
/// `AiPromptManager().loadPrompt('task_advisor.txt')` + `provider.chat()`。
class TaskAdvisor {
  /// 分析任务文档，返回结构化建议卡片列表
  static Future<List<TaskCardModel>> analyze(
      TaskDoc doc, String userInstruction) async {
    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      throw Exception('请先在实验室配置 AI 服务商');
    }

    final systemPrompt = await _buildPrompt(doc, userInstruction);
    final stream = await provider.chat(
      messages: [
        AIMessage(role: 'system', content: systemPrompt),
        AIMessage(role: 'user', content: userInstruction),
      ],
    );

    final sb = StringBuffer();
    await for (final chunk in stream) {
      sb.write(chunk);
    }
    return parseCards(sb.toString());
  }

  /// 应用一个卡片操作，返回新的 markdown（原文档不变）
  static String apply(String markdown, TaskAction action) {
    switch (action.op) {
      case 'addTask':
        return TaskDocParser.insertTask(markdown, action.payload);
      case 'append':
        return TaskDocParser.appendText(markdown, action.payload);
      case 'setDeadline':
        return TaskDocParser.setDeadline(markdown, action.payload.trim());
      case 'addAiNote':
        return TaskDocParser.addAiNote(markdown, action.payload);
      default:
        return markdown;
    }
  }

  /// 宽松解析 AI 返回的 JSON 卡片数组（容忍 ```json 围栏与前后杂文）
  static List<TaskCardModel> parseCards(String raw) {
    var text = raw.trim();
    text = text.replaceFirst(RegExp(r'^```(json)?\s*'), '').trim();
    text = text.replaceFirst(RegExp(r'\s*```$'), '').trim();
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return [];
    final jsonStr = text.substring(start, end + 1);
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.whereType<Map>().map((e) {
        final m = e as Map<String, dynamic>;
        final actions = (m['actions'] as List? ?? const [])
            .whereType<Map>()
            .map((a) => TaskAction(
                  label: a['label']?.toString() ?? '应用',
                  op: a['op']?.toString() ?? 'ignore',
                  payload: a['payload']?.toString() ?? '',
                ))
            .toList();
        return TaskCardModel(
          type: _parseType(m['type']?.toString()),
          title: m['title']?.toString() ?? '建议',
          content: m['content']?.toString() ?? '',
          actions: actions,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static TaskCardType _parseType(String? s) {
    switch (s) {
      case 'priority':
        return TaskCardType.priority;
      case 'energy':
        return TaskCardType.energy;
      case 'breakdown':
        return TaskCardType.breakdown;
      case 'diary':
        return TaskCardType.diary;
      case 'warning':
        return TaskCardType.warning;
      default:
        return TaskCardType.priority;
    }
  }

  /// 组装顾问系统提示词（基础指令 + 文档内容）
  static Future<String> _buildPrompt(
      TaskDoc doc, String userInstruction) async {
    final base = await AiPromptManager().loadPrompt('task_advisor.txt');
    final now = DateTime.now();
    final buf = StringBuffer();
    buf.writeln(base);
    buf.writeln();
    buf.writeln('今天是 ${now.year}年${now.month}月${now.day}日。');
    buf.writeln();
    buf.writeln('=== 任务规划文档 ===');
    buf.writeln('项目：${doc.project.isEmpty ? '(未命名)' : doc.project}');
    buf.writeln('截止：${doc.deadline.isEmpty ? '(未设置)' : doc.deadline}');
    if (doc.goal.isNotEmpty) {
      buf.writeln('目标：');
      buf.writeln('> ${doc.goal}');
    }
    if (doc.milestones.isNotEmpty) {
      buf.writeln('里程碑：');
      for (final m in doc.milestones) {
        buf.writeln('- ${m.checked ? '[x]' : '[ ]'} ${m.text}');
      }
    }
    if (doc.tasks.isNotEmpty) {
      buf.writeln('当前任务：');
      for (final t in doc.tasks) {
        buf.writeln(
            '${'  ' * t.level}- ${t.checked ? '[x]' : '[ ]'} ${t.text}');
      }
    }
    if (doc.diaryRefs.isNotEmpty) {
      buf.writeln('关联日记：');
      for (final r in doc.diaryRefs) {
        buf.writeln('> $r');
      }
    }
    if (doc.aiNotes.isNotEmpty) {
      buf.writeln('已有 AI 建议：');
      for (final n in doc.aiNotes) {
        buf.writeln('> $n');
      }
    }
    buf.writeln('=== 文档结束 ===');
    return buf.toString();
  }
}
