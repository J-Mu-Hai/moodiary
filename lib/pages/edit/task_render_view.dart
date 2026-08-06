import 'package:flutter/material.dart';
import 'package:moodiary/common/models/task_plan.dart';
import 'package:moodiary/services/task_doc_parser.dart';

import 'edit_logic.dart';

/// 任务规划模式的渲染视图（渲染为主，类 Notion）。
///
/// 自研渲染而非 MarkdownWidget，因为可点击复选框需要绑定源行号：
/// 每个任务条目解析时记录 srcLine，点击时翻转 markdown 源文本。
class TaskRenderView extends StatelessWidget {
  const TaskRenderView({super.key, required this.logic});

  final EditLogic logic;

  @override
  Widget build(BuildContext context) {
    final markdown = logic.markdownTextEditingController!.text;
    final pages = TaskDocParser.parsePages(markdown);
    final whole = TaskDocParser.parse(markdown); // 状态栏看整篇
    final idx = logic.state.taskCurrentPage.value;
    final safeIdx = idx >= 0 && idx < pages.length ? idx : 0;
    final current = pages[safeIdx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageTabs(context, pages, safeIdx),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(context, whole),
                if (current.doc.goal.isNotEmpty)
                  _buildGoalCard(context, current.doc),
                if (current.doc.milestones.isNotEmpty)
                  _buildMilestoneSection(context, current.doc),
                _buildTaskSection(context, current.doc),
                if (current.doc.diaryRefs.isNotEmpty)
                  _buildDiarySection(context, current.doc),
                if (current.doc.aiNotes.isNotEmpty)
                  _buildAiNotesSection(context, current.doc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 页面标签栏（`# 页面名` 划分）。单页时隐藏，保持与旧版一致。
  Widget _buildPageTabs(BuildContext context, List<TaskPage> pages, int current) {
    if (pages.length <= 1) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          for (var i = 0; i < pages.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(pages[i].name, style: const TextStyle(fontSize: 12)),
                selected: i == current,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => logic.switchTaskPage(i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context, TaskDoc doc) {
    final colorScheme = Theme.of(context).colorScheme;
    final days = doc.daysUntilDeadline;
    final overdue = doc.overdueDays;
    final progress = (doc.progress * 100).round();

    String deadlineText;
    if (days == null) {
      deadlineText = '未设置截止';
    } else if (days > 0) {
      deadlineText = '还有 $days 天';
    } else if (days == 0) {
      deadlineText = '今天截止';
    } else {
      deadlineText = '已过 ${-days} 天';
    }

    String statusText;
    if (overdue > 0) {
      statusText = '⚠️ 滞后 $overdue 天';
    } else if (days != null && days <= 3) {
      statusText = '⏰ 临近截止';
    } else {
      statusText = '✅ 按计划';
    }

    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🤖 ${doc.project.isEmpty ? '任务规划' : doc.project}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: doc.progress, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Text(
              '进度 $progress% · 截止 $deadlineText · $statusText',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard(BuildContext context, TaskDoc doc) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: colorScheme.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📌 项目目标',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(doc.goal),
        ],
      ),
    );
  }

  Widget _buildMilestoneSection(BuildContext context, TaskDoc doc) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🎯 里程碑',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          for (final m in doc.milestones)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Row(
                children: [
                  Icon(
                    m.checked
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: m.checked ? Colors.green : colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.text,
                      style: TextStyle(
                        decoration: m.checked
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskSection(BuildContext context, TaskDoc doc) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📝 当前阶段任务',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (doc.tasks.isEmpty)
            Text(
              '还没有任务，用引导栏的 ✅ 任务 标签添加',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            )
          else
            for (final t in doc.tasks)
              Padding(
                padding: EdgeInsets.only(
                  left: (t.level * 20).toDouble(),
                  top: 2,
                  bottom: 2,
                ),
                child: InkWell(
                  onTap: () => logic.toggleTask(t.srcLine),
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      Icon(
                        t.checked
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 20,
                        color: t.checked
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.text,
                          style: TextStyle(
                            fontSize: 14,
                            decoration: t.checked
                                ? TextDecoration.lineThrough
                                : null,
                            color: t.checked
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildDiarySection(BuildContext context, TaskDoc doc) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📓 关联日记',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          for (final r in doc.diaryRefs)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.menu_book_rounded,
                      size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAiNotesSection(BuildContext context, TaskDoc doc) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🤖 AI 建议记录',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          for (final n in doc.aiNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '> $n',
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
