import 'package:flutter/material.dart';
import 'package:moodiary/common/models/isar/guide_message.dart';
import 'package:moodiary/common/models/task_guide.dart';
import 'package:moodiary/common/models/task_plan.dart';
import 'package:moodiary/components/chat/chat_bubble.dart';
import 'package:moodiary/pages/assistant/typing_bubble.dart';
import 'package:moodiary/services/task_doc_parser.dart';
import 'package:moodiary/services/task_guide_service.dart';

import 'edit_logic.dart';

/// 右侧任务规划 AI 面板（微信式对话视图）。
///
/// 结构：状态栏（含引导阶段 chip） + 引导对话列表 + 底部输入区。
/// 对话记录在 [EditLogic.state.guideMessages]，操作按钮回调走 [EditLogic.applyGuideAction]。
class TaskPanel extends StatefulWidget {
  const TaskPanel({super.key, required this.logic});

  final EditLogic logic;

  @override
  State<TaskPanel> createState() => _TaskPanelState();
}

class _TaskPanelState extends State<TaskPanel> {
  late final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final s = widget.logic.state;
    s.guideMessages.addListener(_scrollToBottom);
    s.guideAnalyzing.addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    final s = widget.logic.state;
    s.guideMessages.removeListener(_scrollToBottom);
    s.guideAnalyzing.removeListener(_scrollToBottom);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _submit(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    widget.logic.submitGuideInput(trimmed);
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
          Expanded(child: _buildConversation(context)),
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

    // 引导阶段 chip
    final guide = widget.logic.state.guideStage.value;
    final stageLabel = guide >= guideStageDone
        ? '已完成引导'
        : '阶段 $guide/${guideStageDone - 1} · ${TaskGuideStage.fromNo(guide)?.label ?? ''}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '🤖 ${doc.project.isEmpty ? '任务规划' : doc.project} · AI 引导',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 阶段 chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  stageLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
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

  Widget _buildConversation(BuildContext context) {
    final state = widget.logic.state;
    final msgs = state.guideMessages;
    final colorScheme = Theme.of(context).colorScheme;

    if (msgs.isEmpty && !state.guideAnalyzing.value) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'AI 教练会分 7 个阶段帮你制定计划。\n回答它的提问，计划会写进右侧文档。',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      children: [
        // 顶部时间触发提示条
        if (state.guideNotice.value.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              state.guideNotice.value,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(8),
            itemCount: msgs.length + (state.guideAnalyzing.value ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == msgs.length) return const TypingBubble();
              final m = msgs[index];
              switch (m.kind) {
                case 'stageComplete':
                  return _buildStageComplete(context, m);
                case 'systemNotice':
                  return _buildSystemNotice(context, m);
                default:
                  return _buildMessageBubble(context, m);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(BuildContext context, GuideMessage m) {
    final stripped = TaskGuideService.stripActionMarkers(m.content);
    final (tag, text) = _extractTag(stripped);
    final actions = TaskGuideService.parseActions(m.content);
    final isUser = m.role == 'user';
    return ChatBubble(
      content: text,
      isUser: isUser,
      tag: isUser ? null : tag,
      actions: actions,
      onAction: actions.isEmpty ? null : (a) => widget.logic.applyGuideAction(a),
      maxWidthFactor: 0.85,
    );
  }

  /// 阶段完成卡：居中，✅ 阶段N完成 + 输出物一句话
  Widget _buildStageComplete(BuildContext context, GuideMessage m) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '✅ 阶段 ${m.stage} 完成',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            if (m.content.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                m.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSystemNotice(BuildContext context, GuideMessage m) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Text(
        m.content,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  /// 拆【AI补充】/【AI意见】前缀为 tag，正文不显前缀
  (String?, String) _extractTag(String content) {
    final t = content.trim();
    for (final prefix in const ['【AI补充】', '【AI意见】']) {
      if (t.startsWith(prefix)) {
        final tag = prefix.substring(1, prefix.length - 1);
        return (tag, t.substring(prefix.length).trim());
      }
    }
    return (null, t);
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
              hintText: '💬 回答 AI 的问题...',
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
                label: const Text('我不确定', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: () => _submit('我不确定'),
              ),
              ActionChip(
                label: const Text('重新问一次', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: () => _submit('重新问一次，换个说法'),
              ),
              ActionChip(
                label: const Text('跳过本阶段', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: () => _submit('我想跳过这个阶段'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
