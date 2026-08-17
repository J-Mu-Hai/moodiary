import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/components/base/button.dart';
import 'package:moodiary/components/chat/chat_bubble.dart';
import 'package:moodiary/pages/laboratory/laboratory_logic.dart';
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
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
                  // 微信式短提示字，避免长提示占满输入框看起来居中
                  hintText: '说点什么…',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                ),
              ),
            )),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: logic.checkGetAi,
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                minimumSize: const Size(38, 38),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildChatBubble(AIMessage msg, int index) {
      return ChatBubble(
        content: msg.content,
        isUser: msg.role == 'user',
      );
    }

    /// 时间格式（微信式）：今天→"上午/下午 11:27"；昨天→"昨天 上午 11:27"；
    /// 更早→"8月12日 下午 3:05"。
    String fmtChatTime(DateTime t) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(t.year, t.month, t.day);
      String hm(DateTime x) {
        final hh = x.hour;
        final mm = x.minute.toString().padLeft(2, '0');
        return '${hh < 12 ? '上午' : '下午'} $hh:$mm';
      }

      if (day == today) return hm(t);
      if (day == today.subtract(const Duration(days: 1))) {
        return '昨天 ${hm(t)}';
      }
      return '${t.month}月${t.day}日 ${hm(t)}';
    }

    /// 微信式时间标签：首条消息、或与上一条间隔 ≥5 分钟时，显示灰色时间。
    Widget? buildTimeLabel(List<AIMessage> messages, int index) {
      final msg = messages[index];
      final show = index == 0 ||
          msg.time.difference(messages[index - 1].time).inMinutes >= 5;
      if (!show) return null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            fmtChatTime(msg.time),
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
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
      // 微信式：不用默认的 resizeToAvoidBottomInset 让 body 瞬间跳变，
      // 而是关掉它，靠下方 AnimatedPadding 把整块内容随键盘平滑顶起/落下
      // （像抽屉一样拉出），键盘收放时不突兀。
      resizeToAvoidBottomInset: false,
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
      body: AnimatedPadding(
        // 底部随键盘高度动画：键盘弹起时内容像抽屉一样被顶起，
        // 收起时又跟着落下。时长 220ms 与系统键盘动画节奏接近。
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Obx(() {
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
            // 对话列表：点空白处收起输入状态（微信式，点空白退键盘）
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: logic.unFocus,
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
                          final timeLabel =
                              buildTimeLabel(messages.cast<AIMessage>(), index);
                          return Column(
                            children: [
                              if (timeLabel != null) timeLabel,
                              buildChatBubble(messages[index], index),
                            ],
                          );
                        },
                      ),
              ),
            ),
            buildInput(),
          ],
          );
        }),
      ),
    );
  }
}
