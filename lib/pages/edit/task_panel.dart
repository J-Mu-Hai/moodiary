import 'package:flutter/material.dart';
import 'package:moodiary/common/models/task_plan.dart';
import 'package:moodiary/services/task_doc_parser.dart';

import 'edit_logic.dart';

/// 右侧任务规划 AI 面板（固定 360px）。
///
/// 结构：顶部状态栏 + 中部建议卡片流 + 底部输入区。
/// 状态与文档写回都走 [EditLogic]，本组件只负责渲染与回调。
class TaskPanel extends StatefulWidget {
  const TaskPanel({super.key, required this.logic});

  final EditLogic logic;

  @override
  State<TaskPanel> createState() => _TaskPanelState();
}

class _TaskPanelState extends State<TaskPanel> {
  late final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    widget.logic.runTaskAnalysis(trimmed);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final logic = widget.logic;
    final state = logic.state;

    // 同步来自 logic 的预设输入（如 🤖AI 标签填入的 @AI 前缀）
    final pending = state.taskInput.value;
    if (pending.isNotEmpty && pending != _input.text) {
      _input.text = pending;
      _input.selection = TextSelection.collapsed(offset: pending.length);
      state.taskInput.value = '';
    }

    final colorScheme = Theme.of(context).colorScheme;
    final doc = TaskDocParser.parse(logic.markdownTextEditingController!.text);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          _buildStatusBar(context, doc),
          const Divider(height: 1),
          Expanded(child: _buildCardFlow(context)),
          const Divider(height: 1),
          _buildInputArea(context),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, TaskDoc doc) {
    final colorScheme = Theme.of(context).colorScheme;
    final days = doc.daysUntilDeadline;
    final overdue = doc.overdueDays;
    final progress = (doc.progress * 100).round();

    String deadlineText = '未设置截止';
    if (days != null) {
      deadlineText = days >= 0 ? '还有 $days 天' : '已过 ${-days} 天';
    }
    String statusText = '✅ 按计划';
    if (overdue > 0) {
      statusText = '⚠️ 滞后 $overdue 天';
    } else if (days != null && days <= 3) {
      statusText = '⏰ 临近截止';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '🤖 ${doc.project.isEmpty ? '任务规划' : doc.project} · AI 顾问',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: '折叠面板',
                visualDensity: VisualDensity.compact,
                onPressed: widget.logic.toggleTaskPanel,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: doc.progress, minHeight: 6),
          ),
          const SizedBox(height: 6),
          Text(
            '进度 $progress% · 截止 $deadlineText · $statusText',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildCardFlow(BuildContext context) {
    final logic = widget.logic;
    final state = logic.state;
    final colorScheme = Theme.of(context).colorScheme;

    if (state.taskAnalyzing.value) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('AI 分析中...'),
          ],
        ),
      );
    }
    if (state.taskCards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '在下方输入指令，或点引导栏的 🤖AI 标签。\n例如："检查可行性"',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: state.taskCards.length,
      itemBuilder: (context, i) => _buildCard(context, state.taskCards[i]),
    );
  }

  Widget _buildCard(BuildContext context, TaskCardModel card) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_cardIcon(card.type),
                    size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${card.typeLabel} · ${card.title}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(card.content, style: const TextStyle(fontSize: 13)),
            if (card.actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final a in card.actions)
                    ActionChip(
                      label: Text(a.label,
                          style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        if (a.op == 'ignore') {
                          widget.logic.dismissTaskCard(card);
                        } else {
                          widget.logic.applyTaskAction(card, a);
                        }
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _cardIcon(TaskCardType type) {
    switch (type) {
      case TaskCardType.priority:
        return Icons.flag_rounded;
      case TaskCardType.energy:
        return Icons.bolt_rounded;
      case TaskCardType.breakdown:
        return Icons.account_tree_rounded;
      case TaskCardType.diary:
        return Icons.menu_book_rounded;
      case TaskCardType.warning:
        return Icons.warning_amber_rounded;
    }
  }

  Widget _buildInputArea(BuildContext context) {
    final logic = widget.logic;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _input,
            focusNode: logic.taskInputFocusNode,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '💬 输入 @AI 指令或问题...',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: _submit,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('检查可行性', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: () => _submit('检查任务可行性'),
              ),
              ActionChip(
                label: const Text('拆解任务', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: () => _submit('拆解复杂任务'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
