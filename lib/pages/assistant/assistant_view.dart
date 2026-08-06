import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/common/values/border.dart';
import 'package:moodiary/components/base/button.dart';
import 'package:moodiary/components/base/text.dart';
import 'package:moodiary/main.dart';
import 'package:moodiary/pages/laboratory/laboratory_logic.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:refreshed/refreshed.dart';

import 'assistant_logic.dart';
import 'typing_bubble.dart';

class AssistantPage extends StatelessWidget {
  const AssistantPage({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Bind.find<AssistantLogic>();
    final state = Bind.find<AssistantLogic>().state;
    final colorScheme = Theme.of(context).colorScheme;

    Widget buildInput() {
      return Container(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
                child: Focus(
              onKeyEvent: (node, event) {
                // Enter 发送，Shift+Enter 换行
                if (event is KeyDownEvent) {
                  final isEnter =
                      event.logicalKey == LogicalKeyboardKey.enter;
                  if (isEnter && !HardwareKeyboard.instance.isShiftPressed) {
                    logic.checkGetAi();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                focusNode: logic.focusNode,
                controller: logic.textEditingController,
                minLines: 1,
                maxLines: 4,
                maxLength: null,
                decoration: InputDecoration(
                  hintText: '输入问题... (Enter 发送 / Shift+Enter 换行)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22.0),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            )),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: logic.checkGetAi,
              icon: const Icon(Icons.arrow_upward_rounded),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildChatBubble(AIMessage msg, int index) {
      final isUser = msg.role == 'user';
      final bubbleColor = isUser
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh;

      // 头像：AI 在左、用户在右（微信式，头像在气泡外侧，顶部对齐）
      final avatar = CircleAvatar(
        radius: 18,
        backgroundColor: isUser
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
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
        child: MarkdownBlock(
          data: msg.content,
          config: colorScheme.brightness == Brightness.dark
              ? MarkdownConfig.darkConfig
              : MarkdownConfig.defaultConfig,
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
                    maxWidth: MediaQuery.sizeOf(context).width * 0.68,
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

    /// 选择 Provider 和模型的对话框
    Future<void> _showProviderDialog(BuildContext context) async {
      final labLogic = Bind.find<LaboratoryLogic>();
      final providers = labLogic.getProviders();
      if (providers.isEmpty) {
        NoticeUtil.showToast('请先在实验室配置 AI 服务商');
        return;
      }

      final selectedId = state.currentProviderId.value;

      await showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择 AI 服务商'),
          children: providers.map((p) {
            final isSelected = p.id == selectedId;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: Text(p.displayName),
                  subtitle: Text(p.model, style: const TextStyle(fontSize: 12)),
                  value: p.id,
                  groupValue: selectedId,
                  onChanged: (value) {
                    Navigator.pop(ctx);
                    logic.switchProvider(p);
                  },
                ),
                if (isSelected && p.model.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: '模型名',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      controller: TextEditingController(text: p.model),
                      onSubmitted: (newModel) {
                        final updated =
                            p.copyWith(model: newModel);
                        labLogic.updateProvider(p.id, updated);
                        logic.switchModel(newModel);
                      },
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: PageBackButton(onBack: logic.handleBack),
        title: GestureDetector(
          onTap: () => _showProviderDialog(context),
          child: Obx(() {
            final labLogic = Bind.find<LaboratoryLogic>();
            final providers = labLogic.getProviders();
            final currentProvider = providers.cast<AIProviderConfig?>().firstWhere(
                  (p) => p!.id == state.currentProviderId.value,
                  orElse: () => null,
                );
            return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(currentProvider?.displayName ?? 'AI'),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down_rounded,
                      size: 18, color: colorScheme.onSurfaceVariant),
                ],
              );
          }),
        ),
        actions: [
          Obx(() => IconButton(
            onPressed: () => state.diaryAccessEnabled.value = !state.diaryAccessEnabled.value,
            icon: Icon(
              state.diaryAccessEnabled.value
                  ? Icons.menu_book_rounded
                  : Icons.menu_book_outlined,
            ),
            color: state.diaryAccessEnabled.value
                ? colorScheme.primary
                : null,
            tooltip: state.diaryAccessEnabled.value ? '日记感知: 开' : '日记感知: 关',
          )),
          IconButton(
            onPressed: logic.newChat,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '新对话',
          ),
        ],
      ),
      body: Obx(() {
        final messages = state.messages;
        return Column(
          children: [
            // Provider/Model 信息条
            if (state.currentProviderId.value.isNotEmpty)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: colorScheme.surfaceContainerLow,
                child: Text(
                  '模型: ${state.currentModel.value}',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ),
            // 对话列表
            Expanded(
              child: messages.isEmpty && !state.isTyping.value
                  ? Center(
                      child: FaIcon(
                        FontAwesomeIcons.comments,
                        size: 48,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                      ),
                    )
                  : ListView.builder(
                      controller: logic.scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount:
                          messages.length + (state.isTyping.value ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == messages.length) {
                          return const TypingBubble();
                        }
                        return buildChatBubble(messages[index], index);
                      },
                    ),
            ),
            buildInput(),
          ],
        );
      }),
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
