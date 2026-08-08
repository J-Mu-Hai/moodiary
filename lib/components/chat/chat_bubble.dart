import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:moodiary/common/models/task_plan.dart';

/// 微信式聊天气泡（从 assistant_view 提取的公开组件）。
///
/// - [content]：气泡正文（markdown）
/// - [isUser]：true 右侧蓝色、头像在右；false 左侧浅色、头像在左
/// - [tag]：气泡顶部小彩条（如「AI补充」「AI意见」），传 null 不显示
/// - [actions]：气泡内的一排操作按钮（AI 的 [[ACTION:..]] 渲染成按钮）
/// - [onAction]：按钮回调；为空则按钮不显示
/// - [maxWidthFactor]：气泡最大宽度占屏比
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.tag,
    this.actions = const [],
    this.onAction,
    this.maxWidthFactor = 0.68,
  });

  final String content;
  final bool isUser;
  final String? tag;
  final List<TaskAction> actions;
  final void Function(TaskAction)? onAction;
  final double maxWidthFactor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isUser
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;

    // 头像：AI 在左、用户在右（微信式，头像在气泡外侧，顶部对齐）
    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor:
          isUser ? colorScheme.primary : colorScheme.surfaceContainerHighest,
      child: Icon(
        isUser ? Icons.person_rounded : Icons.smart_toy_rounded,
        size: 20,
        color: isUser ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
      ),
    );

    // 气泡主体：贴内容收窄，靠头像侧留小尖角
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isUser ? 14 : 4), // 靠头像侧的小尖角
          bottomRight: Radius.circular(isUser ? 4 : 14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tag != null) _buildTagStrip(context),
          MarkdownBlock(
            data: content,
            config: colorScheme.brightness == Brightness.dark
                ? MarkdownConfig.darkConfig
                : MarkdownConfig.defaultConfig,
          ),
          if (actions.isNotEmpty && onAction != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final a in actions)
                  ActionChip(
                    label: Text(a.label, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onAction!(a),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    // 尾巴小三角，指向头像
    final tail = Positioned(
      top: 12,
      left: isUser ? null : -7,
      right: isUser ? -7 : null,
      child: CustomPaint(
        size: const Size(8, 14),
        painter: _BubbleTailPainter(color: bubbleColor, isLeft: !isUser),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[avatar, const SizedBox(width: 8)],
          Flexible(
            child: IntrinsicWidth(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * maxWidthFactor,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [bubble, tail],
                ),
              ),
            ),
          ),
          if (isUser) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }

  /// 气泡顶的小彩条（tag 标签）
  Widget _buildTagStrip(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = tag == 'AI意见' ? colorScheme.error : colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            tag!,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// 气泡尾巴小三角，尖角指向头像一侧
class _BubbleTailPainter extends CustomPainter {
  _BubbleTailPainter({required this.color, required this.isLeft});

  final Color color;
  final bool isLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isLeft) {
      // 尖朝左（头像在左）：直角边贴气泡左缘
      path.moveTo(0, 4);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else {
      // 尖朝右（头像在右）
      path.moveTo(size.width, 4);
      path.lineTo(0, 0);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isLeft != isLeft;
}
