import 'dart:convert';

import 'package:moodiary/common/models/task_guide.dart';
import 'package:moodiary/common/models/task_plan.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';

/// AI 引导式任务规划的纯函数工具（可单测）。
///
/// 不持有状态；对话编排在 [EditLogic]，本类只负责：
/// - 组装当前阶段的系统提示词（基础教练指令 + 阶段说明 + 文档序列化）
/// - 从流式原文里解析阶段完成回调 `[[CALL:guideComplete|{...}]]`
/// - 解析 / 剥离文档操作标记 `[[ACTION:op|payload]]`
class TaskGuideService {
  /// 组装当前阶段的系统提示词
  static Future<String> buildStagePrompt({
    required TaskDoc doc,
    required int stageNo,
    String? context,
  }) async {
    final base = await AiPromptManager().loadPrompt('task_guide.txt');
    final stage = TaskGuideStage.fromNo(stageNo);
    final now = DateTime.now();
    final buf = StringBuffer();
    buf.writeln(base);
    buf.writeln();
    buf.writeln('=== 当前阶段 ===');
    buf.writeln(
        '当前引导阶段：${stage?.no ?? stageNo}/7（${stage?.label ?? '未知'}）');
    if (stage != null) {
      buf.writeln('本节引导重点与输出物章节：${stage.sectionTitle}');
    }
    if (context != null && context.isNotEmpty) {
      buf.writeln('对话上下文：$context');
    }
    buf.writeln();
    buf.writeln('今天是 ${now.year}年${now.month}月${now.day}日。');
    buf.writeln();
    buf.writeln('=== 任务规划文档 ===');
    buf.writeln('项目：${doc.project.isEmpty ? '(未命名)' : doc.project}');
    buf.writeln('创建于：${doc.created.isEmpty ? '(未记录)' : doc.created}');
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
        buf.writeln('${'  ' * t.level}- ${t.checked ? '[x]' : '[ ]'} ${t.text}');
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

  /// 从 AI 回复原文中解析阶段完成回调。
  /// 用 lastIndexOf 定位（output 正文可能含 `{`/`}`），失败静默返回 null。
  static GuideComplete? parseGuideComplete(String raw) {
    const marker = '[[CALL:guideComplete|';
    final start = raw.lastIndexOf(marker);
    if (start < 0) return null;
    final end = raw.indexOf(']]', start + marker.length);
    if (end < 0) return null;
    final jsonStr = raw.substring(start + marker.length, end);
    try {
      final m = jsonDecode(jsonStr);
      if (m is! Map<String, dynamic>) return null;
      return GuideComplete.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  /// 解析内容里的文档操作标记为按钮列表
  static List<TaskAction> parseActions(String content) {
    final out = <TaskAction>[];
    final re = RegExp(r'\[\[ACTION:(\w+)\|([^\]]+)\]\]');
    for (final m in re.allMatches(content)) {
      final op = m.group(1)!;
      out.add(TaskAction(
        label: _actionLabel(op),
        op: op,
        payload: m.group(2)!,
      ));
    }
    return out;
  }

  /// 剥离文档操作标记，保留正文
  static String stripActionMarkers(String content) {
    return content.replaceAll(RegExp(r'\[\[ACTION:\w+\|[^\]]+\]\]'), '');
  }

  static String _actionLabel(String op) {
    switch (op) {
      case 'addTask':
        return '➕ 加为任务';
      case 'setDeadline':
        return '📅 设置截止';
      case 'append':
        return '📎 追加到文档';
      case 'addAiNote':
        return '💡 记入建议';
      default:
        return '✅ 应用';
    }
  }

  /// 剥离引导完成回调标记（保留其余正文）
  static String stripGuideCompleteMarker(String content) {
    return content.replaceAll(RegExp(r'\[\[CALL:guideComplete\|[^\]]*\]\]'), '');
  }
}
