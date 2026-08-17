import 'dart:io';

import 'package:flutter/material.dart';
import 'package:moodiary/common/models/isar/usage_session.dart';
import 'package:moodiary/common/values/border.dart';
import 'package:moodiary/components/base/button.dart';
import 'package:moodiary/services/memory_service.dart';
import 'package:moodiary/utils/session_merger.dart';
import 'package:refreshed/refreshed.dart';

import 'screen_time_logic.dart';
import 'screen_time_state.dart';

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

    String fmtHM(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    String dayLabel(DateTime d) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (d == today) return '今天';
      if (d == today.subtract(const Duration(days: 1))) return '昨天';
      return '${d.month}/${d.day}';
    }

    String fmtTime(DateTime t) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(t.year, t.month, t.day);
      final hm = fmtHM(t);
      if (d == today) return '今天 $hm';
      return '${t.month}/${t.day} $hm';
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

    // 持续监督开关（仅 Android）
    Widget buildMonitorCard() {
      return Card.filled(
        color: colorScheme.surfaceContainer,
        child: SwitchListTile(
          value: state.monitoringEnabled,
          onChanged: state.monitorBusy ? null : (_) => logic.toggleMonitoring(),
          secondary: Icon(Icons.radar, color: colorScheme.primary),
          title: const Text('持续监督'),
          subtitle: Text(
            state.monitoringEnabled
                ? '开启中：每分钟采集一次，退出应用后仍持续'
                : '关闭：仅在打开应用时采集（每 5 分钟）',
            style: textStyle.bodySmall,
          ),
        ),
      );
    }

    // 总览 / 时间线切换
    Widget buildViewSwitcher() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SegmentedButton<UsageViewMode>(
          segments: const [
            ButtonSegment(
              value: UsageViewMode.overview,
              icon: Icon(Icons.pie_chart_outline),
              label: Text('总览'),
            ),
            ButtonSegment(
              value: UsageViewMode.timeline,
              icon: Icon(Icons.timeline),
              label: Text('时间线'),
            ),
          ],
          selected: {state.viewMode},
          onSelectionChanged: (s) => logic.selectView(s.first),
          showSelectedIcon: false,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 44,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  state.loading ? '加载中...' : '暂无使用记录',
                  style: textStyle.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                if (!state.loading) ...[
                  const SizedBox(height: 8),
                  Text(
                    '在手机端系统设置中开启"使用情况访问"，点右上角刷新后，'
                    '这里会按天展示各应用的使用时长。',
                    textAlign: TextAlign.center,
                    style: textStyle.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      final maxMs = state.records.first.foregroundMs;
      // 兜底：只渲染前 30 条，防止历史累积数据把主线程打爆
      final displayRecords = state.records.take(30).toList();
      return Card.filled(
        color: colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final r in displayRecords) ...[
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

    // 单条会话（时间段 + 应用 + 时长）
    Widget buildSessionRow(UsageSession s) {
      final endLabel = s.isOpen ? '现在' : fmtHM(s.end!);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                '${fmtHM(s.start)}\n$endLabel',
                style: textStyle.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.isOpen
                    ? colorScheme.error
                    : colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      s.appName.isEmpty ? s.packageName : s.appName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (s.isOpen) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: AppBorderRadius.smallBorderRadius,
                      ),
                      child: Text(
                        '进行中',
                        style: textStyle.labelSmall
                            ?.copyWith(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              fmtDuration(s.durationMs),
              style: textStyle.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // 时间线：按时间段还原"什么时间段用了什么应用"
    Widget buildTimeline() {
      if (state.sessions.isEmpty) {
        return Card.filled(
          color: colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timeline,
                  size: 44,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  state.loading ? '加载中...' : '暂无时间线记录',
                  style: textStyle.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                if (!state.loading) ...[
                  const SizedBox(height: 8),
                  Text(
                    '打开"持续监督"后，这里会按时间段展示每个应用的使用情况；'
                    '红点表示该应用当前正在使用。',
                    textAlign: TextAlign.center,
                    style: textStyle.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      // 显示层合并相邻同应用碎片（纯函数，不改动本地数据）
      final display = mergeAdjacentSessions(state.sessions);
      return Card.filled(
        color: colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (final (i, s) in display.indexed) ...[
                if (i > 0)
                  Divider(height: 1, color: colorScheme.surfaceContainerHighest),
                buildSessionRow(s),
              ],
            ],
          ),
        ),
      );
    }

    // 画像类别 → 颜色（直观区分沉淀的认知类型）
    Color categoryColor(String cat) {
      switch (cat) {
        case '生活习惯':
          return Colors.blue;
        case '情绪状态':
          return Colors.deepOrange;
        case '偏好与习惯':
          return Colors.purple;
        case '目标与痛点':
          return Colors.teal;
        case '人际关系':
          return Colors.pink;
        case '行为规律':
          return Colors.green;
        default:
          return colorScheme.primary;
      }
    }

    // 用户画像面板：直接观察智能体沉淀的长期认知（阶段 1/2 记忆层可视化）
    Widget buildProfilePanel() {
      final data = state.memoryData;

    // 单条认知：内容 + 置信度/来源（类别标签已在分类标题行展示）
    Widget _profileEntryRow(ProfileEntry e) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.content, style: textStyle.bodyMedium),
                  const SizedBox(height: 1),
                  Text(
                    '置信 ${e.confidence.toStringAsFixed(1)} · '
                    '${profileSourceLabel(e.source)}',
                    style: textStyle.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

      return Card.filled(
        color: colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('用户画像', style: textStyle.titleMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: state.memoryLoading ? null : logic.loadMemory,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: '刷新画像',
                  ),
                  IconButton(
                    onPressed: state.memoryLoading
                        ? null
                        : () async {
                            final summary = await logic.consolidateMemory();
                            if (!context.mounted) return;
                            await showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('画像沉淀结果'),
                                content: SelectionArea(
                                  child: Text(summary,
                                      style: const TextStyle(fontSize: 13)),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: const Text('好的'),
                                  ),
                                ],
                              ),
                            );
                          },
                    icon: const Icon(Icons.auto_awesome, size: 20),
                    tooltip: '立即沉淀',
                  ),
                ],
              ),
              if (data != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '版本 v${data.profileVersion} · 更新于 ${fmtTime(data.updatedAt)}',
                    style: textStyle.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (data.entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '暂无画像。\n写几篇日记后点右上角自动图标立即沉淀。',
                        textAlign: TextAlign.center,
                        style: textStyle.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      // 9 大类结构常驻：始终渲染全部类别（含空的「待沉淀」），
                      // 每条认知带置信度与来源徽标。
                      itemCount: profileCategories.length,
                      itemBuilder: (_, ci) {
                        final cat = profileCategories[ci];
                        final items = data.categories[cat] ?? const [];
                        final catColor = categoryColor(cat);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 8, bottom: 2),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: catColor.withValues(alpha: 0.15),
                                      borderRadius:
                                          AppBorderRadius.smallBorderRadius,
                                    ),
                                    child: Text(
                                      cat,
                                      style: textStyle.labelSmall
                                          ?.copyWith(color: catColor),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    items.isEmpty ? '待沉淀' : '${items.length} 条',
                                    style: textStyle.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (items.isNotEmpty)
                              ...items.map((e) => _profileEntryRow(e)),
                          ],
                        );
                      },
                    ),
                  ),
              ] else if (state.memoryLoading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      '画像读取失败',
                      style: textStyle.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
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
            onPressed: logic.reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
          ),
        ],
      ),
      body: GetBuilder<ScreenTimeLogic>(builder: (_) {
        return LayoutBuilder(builder: (context, constraints) {
          // 宽屏（电脑/平板横屏）左右分栏：使用时间 | 用户画像
          final wide = constraints.maxWidth >= 720;
          final usageList = ListView(
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
              // 持续监督开关（仅手机端）
              if (Platform.isAndroid) buildMonitorCard(),
              // 总览 / 时间线切换
              buildViewSwitcher(),
              // 后台采集/同步期间显示细进度条，让用户感知到页面在工作
              if (state.loading)
                const LinearProgressIndicator(minHeight: 2),
              // 数据新鲜度提示：明确告知数据何时更新，避免"看起来没反应"
              if (state.loadedAt != null && !state.loading)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    '数据更新于 ${fmtTime(state.loadedAt!)}',
                    style: textStyle.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (state.viewMode == UsageViewMode.overview) ...[
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
              ] else
                buildTimeline(),
            ],
          );
          final profilePanel = buildProfilePanel();

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: usageList),
                VerticalDivider(width: 1, color: colorScheme.outlineVariant),
                SizedBox(width: 360, child: profilePanel),
              ],
            );
          }
          // 窄屏（手机竖屏）：使用时间在上，画像在下
          return Column(
            children: [
              Expanded(child: usageList),
              Divider(height: 1, color: colorScheme.outlineVariant),
              SizedBox(
                height: constraints.maxHeight * 0.42,
                child: profilePanel,
              ),
            ],
          );
        });
      }),
    );
  }
}
