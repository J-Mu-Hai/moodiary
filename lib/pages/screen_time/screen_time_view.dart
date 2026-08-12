import 'dart:io';

import 'package:flutter/material.dart';
import 'package:moodiary/common/values/border.dart';
import 'package:moodiary/components/base/button.dart';
import 'package:refreshed/refreshed.dart';

import 'screen_time_logic.dart';

class ScreenTimePage extends StatelessWidget {
  const ScreenTimePage({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Bind.find<ScreenTimeLogic>();
    final state = Bind.find<ScreenTimeLogic>().state;
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;

    String fmtDuration(int ms) {
      final totalMinutes = (ms / 60000).round();
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;
      if (h > 0) return '${h}小时${m}分钟';
      return '${m}分钟';
    }

    String dayLabel(DateTime d) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (d == today) return '今天';
      if (d == today.subtract(const Duration(days: 1))) return '昨天';
      return '${d.month}/${d.day}';
    }

    // 未授权横幅（仅 Android）
    Widget buildPermissionBanner() {
      return Card.filled(
        color: colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.timer_off_outlined, color: colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '需在系统设置中开启"使用情况访问"才能统计手机应用使用时长。',
                  style: textStyle.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: logic.openSettings,
                child: const Text('去授权'),
              ),
            ],
          ),
        ),
      );
    }

    // 当日总时长
    Widget buildTotal() {
      final totalMs = state.records.fold<int>(0, (s, r) => s + r.foregroundMs);
      return Card.filled(
        color: colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text('当日总使用', style: textStyle.titleMedium),
              const Spacer(),
              Text(
                fmtDuration(totalMs),
                style: textStyle.titleLarge?.copyWith(color: colorScheme.primary),
              ),
            ],
          ),
        ),
      );
    }

    // 各应用时长列表（相对当日最大值归一）
    Widget buildRecords() {
      if (state.records.isEmpty) {
        return Card.filled(
          color: colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                state.loading ? '加载中...' : '暂无使用记录',
                style: textStyle.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        );
      }
      final maxMs = state.records.first.foregroundMs;
      return Card.filled(
        color: colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final r in state.records) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(r.appName, overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      fmtDuration(r.foregroundMs),
                      style: textStyle.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: AppBorderRadius.smallBorderRadius,
                  child: LinearProgressIndicator(
                    value: maxMs == 0 ? 0 : r.foregroundMs / maxMs,
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('使用时间'),
        leading: const PageBackButton(),
        actions: [
          IconButton(
            onPressed: logic.refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: GetBuilder<ScreenTimeLogic>(builder: (_) {
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (Platform.isAndroid && !state.granted) buildPermissionBanner(),
            // 日期选择
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: state.recentDays.map((d) {
                  final selected = d == state.selectedDate;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(dayLabel(d)),
                      selected: selected,
                      onSelected: (_) => logic.selectDate(d),
                    ),
                  );
                }).toList(),
              ),
            ),
            buildTotal(),
            if (!Platform.isAndroid)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '数据来自手机端采集，电脑端仅展示与同步',
                  style: textStyle.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            buildRecords(),
          ],
        );
      }),
    );
  }
}
