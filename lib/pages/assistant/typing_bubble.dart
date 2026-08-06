import 'package:flutter/material.dart';

/// 打字指示器气泡 — 微信风格：三个错相循环的圆点
///
/// 随 isTyping=false 从列表移除时自动 dispose，无泄漏。
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        // 左偏移对齐 AI 气泡内容（头像 36 + 间距 8 + 列表 padding 8）
        padding: const EdgeInsets.only(top: 4, bottom: 4, left: 52, right: 64),
        child: Card(
          color: colorScheme.surfaceContainerHigh, // 与 AI 气泡同色
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    // 三个圆点错相：每个落后 1/3 周期
                    final phase = (_controller.value + i * 0.33) % 1.0;
                    final a = 0.25 +
                        0.75 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            colorScheme.onSurfaceVariant.withValues(alpha: a),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
