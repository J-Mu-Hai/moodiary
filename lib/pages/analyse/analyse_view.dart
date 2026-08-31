import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:moodiary/common/values/icons.dart';
import 'package:moodiary/components/base/button.dart';
import 'package:moodiary/components/mood_icon/mood_icon_view.dart';
import 'package:moodiary/main.dart';
import 'package:moodiary/services/agent_brain/behavior_model.dart';
import 'package:moodiary/utils/array_util.dart';
import 'package:moodiary/utils/notice_util.dart';
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
            // 智能体行为认知只读卡：智能体自主归纳的 24h 行为作息 + 重新建模
            const _BehaviorModelCard(),
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

/// 智能体行为认知只读卡 — 展示智能体自动归纳的 24h 行为作息 + 重新建模按钮。
///
/// 自包含加载：先展示本地模型与聚合，再后台拉一次跨端元数据
/// （behaviorObservations 在快同步清单里，拉到远端新观察后重算聚合），
/// 保持手机/电脑两边一致。按钮直接调 BehaviorModelStore.build()（AI 归纳落库）。
class _BehaviorModelCard extends StatefulWidget {
  const _BehaviorModelCard();

  @override
  State<_BehaviorModelCard> createState() => _BehaviorModelCardState();
}

class _BehaviorModelCardState extends State<_BehaviorModelCard> {
  BehaviorModel? _model;
  String _aggregation = '';
  String _currentWindow = '';
  bool _building = false; // 「重新建模」转圈
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    // 先展示本地，再后台拉远端观察（WebDAV 未配置时 syncMetadata 内部
    // _client == null 直接返回，安全 no-op）。
    unawaited(WebDavUtil()
        .syncMetadata(pullOnly: true)
        .timeout(const Duration(seconds: 20), onTimeout: () {})
        .then((_) {
      if (mounted) _reload();
    }));
    if (mounted) _reload();
  }

  Future<void> _reload() async {
    final m = await BehaviorModelStore.load();
    final agg = await BehaviorModelStore.aggregationText();
    final cur = await BehaviorModelStore.currentWindowText(DateTime.now());
    if (!mounted) return;
    setState(() {
      _model = m;
      _aggregation = agg;
      _currentWindow = cur;
      _loading = false;
    });
  }

  /// 重新建模：AI 归纳 + 落库，转圈提示，完成后刷新。
  Future<void> _rebuild() async {
    if (_building) return;
    setState(() => _building = true);
    final msg = await BehaviorModelStore.build();
    if (!mounted) return;
    setState(() => _building = false);
    NoticeUtil.showToast(msg);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;
    final narrative = _model == null || (_model!.narrative.isEmpty)
        ? '（尚未建模，将自动归纳）'
        : _model!.narrative;
    return Card.filled(
      color: colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_outlined,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('智能体行为认知（自主归纳你的 24h 作息）',
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
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('加载中…', style: TextStyle(fontSize: 12)),
              )
            else ...[
              Text(
                '智能体归纳：$narrative',
                style: textStyle.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text('近7天手机观察（自动归纳）',
                    style: textStyle.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectionArea(
                      child: Text(
                        _aggregation,
                        style: textStyle.bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '当前对应时段：$_currentWindow',
                style: textStyle.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _building ? null : _rebuild,
                icon: _building
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(_building ? '建模中…' : '重新建模'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
