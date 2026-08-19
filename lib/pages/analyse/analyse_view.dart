import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:moodiary/common/values/icons.dart';
import 'package:moodiary/components/base/button.dart';
import 'package:moodiary/components/mood_icon/mood_icon_view.dart';
import 'package:moodiary/main.dart';
import 'package:moodiary/router/app_routes.dart';
import 'package:moodiary/services/agent_brain/daily_routine.dart';
import 'package:moodiary/utils/array_util.dart';
import 'package:moodiary/utils/webdav_util.dart';
import 'package:refreshed/refreshed.dart';

import 'analyse_logic.dart';

class AnalysePage extends StatelessWidget {
  const AnalysePage({super.key});

  @override
  Widget build(BuildContext context) {
    final logic = Bind.find<AnalyseLogic>();
    final state = Bind.find<AnalyseLogic>().state;
    final textStyle = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);

    //柱状图
    Widget buildBarChart(Map<String, IconData> iconMap,
        Map<String, int> countMap, List<String> itemList) {
      //去重
      itemList = ArrayUtil.toSetList(itemList);
      return Card.filled(
        color: colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: itemList.isNotEmpty
                ? BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      borderData: FlBorderData(
                        show: true,
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: colorScheme.onSurface
                                .withAlpha((255 * 0.6).toInt()),
                          ),
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1.0,
                                getTitlesWidget: (value, meta) {
                                  return Text(value.toInt().toString());
                                })),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                return SideTitleWidget(
                                    meta: meta,
                                    child:
                                        Icon(iconMap[itemList[value.toInt()]]));
                              }),
                        ),
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        checkToShowHorizontalLine: (value) {
                          return value.toInt() == value;
                        },
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: colorScheme.onSurface
                                .withAlpha((255 * 0.2).toInt()),
                            strokeWidth: 1,
                          );
                        },
                      ),
                      barGroups: List.generate(
                        itemList.length,
                        (index) => BarChartGroupData(x: index, barRods: [
                          BarChartRodData(
                              fromY: 0,
                              toY: countMap[itemList[index]]!.toDouble(),
                              color: colorScheme.primary)
                        ]),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (state.finished) ...[
                        Text(
                          '暂无数据',
                          style: textStyle.titleLarge!
                              .copyWith(color: colorScheme.onSurface),
                        ),
                      ] else ...[
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
          ),
        ),
      );
    }

    Widget buildMoodWrap(List<double> itemList) {
      return Card.filled(
        color: colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: itemList.isNotEmpty
                ? Center(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: List.generate(state.moodList.length, (index) {
                          return MoodIconComponent(
                              value: state.moodList[index]);
                        }),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (state.finished) ...[
                        Text(
                          '暂无数据',
                          style: textStyle.titleLarge!
                              .copyWith(color: colorScheme.onSurface),
                        ),
                      ] else ...[
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.settingFunctionAnalysis,
        ),
        leading: const PageBackButton(),
      ),
      body: GetBuilder<AnalyseLogic>(builder: (_) {
        return ListView(
          padding: const EdgeInsets.all(4.0),
          children: [
            Card.filled(
              color: colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  spacing: 8.0,
                  children: [
                    IconButton.filled(
                        onPressed: () {
                          logic.openDatePicker(context);
                        },
                        icon: const Icon(Icons.date_range)),
                    Text(
                      '${state.dateRange[0].year}年${state.dateRange[0].month}月${state.dateRange[0].day}日 至 ${state.dateRange[1].year}年${state.dateRange[1].month}月${state.dateRange[1].day}日',
                    ),
                  ],
                ),
              ),
            ),
            Card.filled(
              color: colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    TextButton(
                        onPressed: () {
                          logic.getAi();
                        },
                        child: const Text('AI 分析')),
                    if (state.reply != '') ...[Text(state.reply)]
                  ],
                ),
              ),
            ),
            // 行为作息入口卡：用户自定义作息表 + 手机监督（进入独立页面编辑）
            const _RoutineEntryCard(),
            GridView.count(
              crossAxisCount: size.width > 600 ? 2 : 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                buildBarChart(
                    WeatherIcon.map, state.weatherMap, state.weatherList),
                buildMoodWrap(state.moodList)
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// 行为作息入口卡 — 用户自定义的 24h 作息表 + 手机监督，点按钮进入独立页面编辑。
///
/// 自包含加载：先展示本地作息表，再后台拉一次跨端元数据（dailyRoutine 在
/// 快同步清单里），保持手机/电脑两边一致。
class _RoutineEntryCard extends StatefulWidget {
  const _RoutineEntryCard();

  @override
  State<_RoutineEntryCard> createState() => _RoutineEntryCardState();
}

class _RoutineEntryCardState extends State<_RoutineEntryCard> {
  RoutineSchedule? _schedule;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await DailyRoutineStore.load();
    // 作息表在跨端快同步清单里：后台拉一次远端变化，有更新再刷新本地展示。
    // WebDAV 未配置时 syncMetadata 内部 _client == null 直接返回，安全 no-op。
    unawaited(WebDavUtil()
        .syncMetadata(pullOnly: true)
        .timeout(const Duration(seconds: 20), onTimeout: () {})
        .then((_) {
      if (mounted) _reload();
    }));
    if (mounted) {
      setState(() {
        _schedule = s;
        _now = DateTime.now();
      });
    }
  }

  Future<void> _reload() async {
    final s = await DailyRoutineStore.load();
    if (!mounted) return;
    setState(() {
      _schedule = s;
      _now = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;
    final s = _schedule;
    return Card.filled(
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('行为作息（你的每日时段 · 身份 × 做什么）',
                    style: textStyle.titleSmall),
                const Spacer(),
                IconButton(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  tooltip: '刷新',
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (s == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('加载中…', style: TextStyle(fontSize: 12)),
              )
            else if (s.slots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '还没有作息表：点「管理作息表」定义你的 24 小时作息，'
                  '智能体会用它对照手机观察，分析你的真实行为',
                  style: TextStyle(fontSize: 12),
                ),
              )
            else ...[
              Text(
                '${s.defaultIdentity.trim().isEmpty ? '' : '日常身份：${s.defaultIdentity.trim()} · '}'
                '现在 ${DailyRoutineStore.fmtMm(_now.hour * 60 + _now.minute)}，'
                '按你的作息应为：${DailyRoutineStore.currentSlotText(s, _now)}',
                style: textStyle.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                DailyRoutineStore.summaryText(s),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textStyle.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Get.toNamed(AppRoutes.routinePage);
                  if (mounted) _reload();
                },
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('管理作息表'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
