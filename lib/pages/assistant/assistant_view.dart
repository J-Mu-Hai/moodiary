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
      return Padding(
        padding: EdgeInsets.only(
          left: isUser ? 64 : 0,
          right: isUser ? 0 : 64,
          top: 4,
          bottom: 4,
        ),
        child: Card(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isUser ? Icons.person_rounded : Icons.smart_toy_rounded,
                      size: 16,
                      color: isUser
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isUser ? '你' : 'AI',
                      style: TextStyle(
                        fontSize: 12,
                        color: isUser
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MarkdownBlock(
                  data: msg.content.isEmpty
                      ? (isUser ? '' : '...')
                      : msg.content,
                  config: colorScheme.brightness == Brightness.dark
                      ? MarkdownConfig.darkConfig
                      : MarkdownConfig.defaultConfig,
                ),
              ],
            ),
          ),
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
