import 'package:flutter/material.dart';
import 'package:moodiary/components/base/button.dart';
import 'package:moodiary/services/agent_brain/daily_routine.dart';
import 'package:refreshed/refreshed.dart';

import 'routine_logic.dart';

/// 行为作息页：编辑「日常身份 + 24h 时段（身份×做什么）」，展示手机监督。
class RoutinePage extends StatelessWidget {
  const RoutinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Bind.find<RoutineLogic>();
    final textStyle = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('行为作息'),
        leading: const PageBackButton(),
      ),
      body: GetBuilder<RoutineLogic>(builder: (_) {
        final state = logic.state;
        return ListView(
          padding: const EdgeInsets.all(4.0),
          children: [
            // ── 日常身份 ──
            Card.filled(
              color: colorScheme.surfaceContainer,
              child: ListTile(
                leading: Icon(Icons.badge_outlined, color: colorScheme.primary),
                title: const Text('日常身份'),
                subtitle: Text(
                  state.defaultIdentity.trim().isNotEmpty
                      ? state.defaultIdentity.trim()
                      : '（未设置，如「学生」）',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => logic.editDefaultIdentity(context),
                ),
              ),
            ),

            // ── 手机监督 ──
            Card.filled(
              color: colorScheme.surfaceContainer,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                    child: Row(
                      children: [
                        Icon(Icons.monitor_heart_outlined,
                            size: 18, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('手机监督 · 你的计划 vs 实际',
                            style: textStyle.titleSmall),
                        const Spacer(),
                        IconButton(
                          onPressed: () => logic.refreshSupervision(),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          tooltip: '刷新',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SelectionArea(
                      child: Text(
                        state.supervisionText.isEmpty
                            ? '加载中…'
                            : state.supervisionText,
                        style: textStyle.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 时段列表 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('时段列表', style: textStyle.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => logic.addSlot(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加时段'),
                  ),
                ],
              ),
            ),
            if (state.slots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '还没有时段：点击「添加时段」定义你的 24 小时作息，'
                  '智能体会用它对照手机观察，分析你的真实行为',
                  style: TextStyle(fontSize: 12),
                ),
              )
            else
              ...state.slots.map((slot) => ListTile(
                    dense: true,
                    leading: Icon(Icons.schedule,
                        size: 18, color: colorScheme.primary),
                    title: Text(
                      '${DailyRoutineStore.fmtSlot(slot)} '
                      '${_identity(slot, state.defaultIdentity)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      slot.activity.trim().isEmpty
                          ? '（未填）'
                          : slot.activity.trim(),
                      style: textStyle.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => logic.editSlot(context, slot),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: colorScheme.error),
                          onPressed: () => logic.deleteSlot(slot),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 24),
          ],
        );
      }),
    );
  }

  static String _identity(RoutineSlot slot, String defaultIdentity) {
    final id = slot.identity.trim().isNotEmpty
        ? slot.identity.trim()
        : defaultIdentity.trim();
    return id.isEmpty ? '' : id;
  }
}
