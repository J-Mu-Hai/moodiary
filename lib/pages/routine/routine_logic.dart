import 'dart:async';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:moodiary/services/agent_brain/daily_routine.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:refreshed/refreshed.dart';

import 'routine_state.dart';

/// 行为作息页逻辑：编辑「日常身份 + 24h 时段（身份×做什么）」，
/// 并展示手机监督（计划 vs 智能体观察到的实际）。
class RoutineLogic extends GetxController {
  final RoutineState state = RoutineState();

  @override
  void onReady() {
    reload();
    super.onReady();
  }

  /// 重新加载作息表 + 重算手机监督。
  Future<void> reload() async {
    final s = await DailyRoutineStore.load();
    state.defaultIdentity = s.defaultIdentity;
    state.slots = s.sorted;
    state.currentSlotText =
        DailyRoutineStore.currentSlotText(s, DateTime.now());
    state.supervisionText = await DailyRoutineStore.supervisionText(s);
    update();
  }

  /// 重算手机监督（页面点刷新按钮用）。
  Future<void> refreshSupervision() async {
    final s = await DailyRoutineStore.load();
    state.currentSlotText =
        DailyRoutineStore.currentSlotText(s, DateTime.now());
    state.supervisionText = await DailyRoutineStore.supervisionText(s);
    update();
  }

  /// 编辑日常身份（单字段对话框）。
  Future<void> editDefaultIdentity(BuildContext context) async {
    final res = await showTextInputDialog(
      context: context,
      title: '日常身份',
      message: '你通常是怎样的身份？（如：学生、上班族）',
      textFields: [
        DialogTextField(
          hintText: '如：学生',
          initialText: state.defaultIdentity,
        ),
      ],
      style: AdaptiveStyle.material,
    );
    if (res == null || res.isEmpty) return;
    final s = await DailyRoutineStore.load();
    s.defaultIdentity = res.first.trim();
    await DailyRoutineStore.save(s);
    await reload();
  }

  /// 新增一个时段（校验重叠后落库）。
  Future<void> addSlot(BuildContext context) async {
    final s = await DailyRoutineStore.load();
    if (!context.mounted) return;
    final result = await showSlotEditDialog(
      context,
      existing: null,
      defaultIdentity: s.defaultIdentity,
    );
    if (result == null) return;
    final slot = result.toSlot('r${DateTime.now().millisecondsSinceEpoch}');
    if (DailyRoutineStore.hasOverlap(s.slots, slot)) {
      NoticeUtil.showToast('时间段与已有时段重叠，请检查');
      return;
    }
    s.slots.add(slot);
    await DailyRoutineStore.save(s);
    await reload();
  }

  /// 编辑一个时段（排除自身后校验重叠）。
  Future<void> editSlot(BuildContext context, RoutineSlot slot) async {
    final s = await DailyRoutineStore.load();
    if (!context.mounted) return;
    final result = await showSlotEditDialog(
      context,
      existing: slot,
      defaultIdentity: s.defaultIdentity,
    );
    if (result == null) return;
    final updated = result.toSlot(slot.id);
    final others = s.slots.where((o) => o.id != slot.id).toList();
    if (DailyRoutineStore.hasOverlap(others, updated)) {
      NoticeUtil.showToast('时间段与已有时段重叠，请检查');
      return;
    }
    s.slots.removeWhere((o) => o.id == slot.id);
    s.slots.add(updated);
    await DailyRoutineStore.save(s);
    await reload();
  }

  /// 删除一个时段。
  Future<void> deleteSlot(RoutineSlot slot) async {
    final s = await DailyRoutineStore.load();
    s.slots.removeWhere((o) => o.id == slot.id);
    await DailyRoutineStore.save(s);
    await reload();
  }
}

/// 时段编辑对话框的结果（分钟数 + 身份 + 做什么）。
class RoutineSlotEditResult {
  final int startMinute;
  final int endMinute;
  final String identity;
  final String activity;

  const RoutineSlotEditResult({
    required this.startMinute,
    required this.endMinute,
    required this.identity,
    required this.activity,
  });

  RoutineSlot toSlot(String id) => RoutineSlot(
        id: id,
        startMinute: startMinute,
        endMinute: endMinute,
        identity: identity.trim(),
        activity: activity.trim(),
      );
}

/// 打开时段编辑对话框（项目首个「开始/结束双时间选择」表单）。
Future<RoutineSlotEditResult?> showSlotEditDialog(
  BuildContext context, {
  RoutineSlot? existing,
  String defaultIdentity = '',
}) {
  return showDialog<RoutineSlotEditResult>(
    context: context,
    builder: (_) => _SlotEditDialog(
      existing: existing,
      defaultIdentity: defaultIdentity,
    ),
  );
}

class _SlotEditDialog extends StatefulWidget {
  final RoutineSlot? existing;
  final String defaultIdentity;

  const _SlotEditDialog({this.existing, this.defaultIdentity = ''});

  @override
  State<_SlotEditDialog> createState() => _SlotEditDialogState();
}

class _SlotEditDialogState extends State<_SlotEditDialog> {
  late TimeOfDay _start;
  late TimeOfDay _end;
  late final TextEditingController _identity;
  late final TextEditingController _activity;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _start = e != null
        ? TimeOfDay(hour: e.startMinute ~/ 60, minute: e.startMinute % 60)
        : const TimeOfDay(hour: 8, minute: 0);
    _end = e != null
        ? TimeOfDay(hour: e.endMinute ~/ 60, minute: e.endMinute % 60)
        : const TimeOfDay(hour: 12, minute: 0);
    _identity = TextEditingController(text: e?.identity ?? widget.defaultIdentity);
    _activity = TextEditingController(text: e?.activity ?? '');
  }

  @override
  void dispose() {
    _identity.dispose();
    _activity.dispose();
    super.dispose();
  }

  int get _startMinute => _start.hour * 60 + _start.minute;
  int get _endMinute => _end.hour * 60 + _end.minute;

  Future<void> _pick(BuildContext context, bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final isCrossDay = _endMinute < _startMinute;
    final isFullDay = _endMinute == _startMinute;

    String hint;
    if (isFullDay) {
      hint = '全天（任意时刻）';
    } else if (isCrossDay) {
      hint = '跨天：${_fmt(_start)} 到次日 ${_fmt(_end)}';
    } else {
      hint = '${_fmt(_start)} 到 ${_fmt(_end)}';
    }

    return AlertDialog(
      title: Text(widget.existing == null ? '添加时段' : '编辑时段'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('开始时间'),
              trailing: Text(_fmt(_start),
                  style: textStyle.titleMedium
                      ?.copyWith(color: colorScheme.primary)),
              onTap: () => _pick(context, true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('结束时间'),
              trailing: Text(_fmt(_end),
                  style: textStyle.titleMedium
                      ?.copyWith(color: colorScheme.primary)),
              onTap: () => _pick(context, false),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(hint,
                    style: textStyle.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant)),
              ),
            ),
            TextField(
              controller: _identity,
              decoration: const InputDecoration(
                labelText: '身份',
                hintText: '如：学生',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _activity,
              decoration: const InputDecoration(
                labelText: '做什么',
                hintText: '如：睡觉 / 学习',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(
              context,
              RoutineSlotEditResult(
                startMinute: _startMinute,
                endMinute: _endMinute,
                identity: _identity.text,
                activity: _activity.text,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
