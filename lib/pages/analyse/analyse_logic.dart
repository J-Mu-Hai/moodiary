import 'dart:convert';

import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/material.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/services/ai_functions.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/utils/array_util.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:refreshed/refreshed.dart';

import 'analyse_state.dart';

class AnalyseLogic extends GetxController {
  final AnalyseState state = AnalyseState();

  @override
  void onReady() async {
    await getMoodAndWeatherByRange(state.dateRange[0], state.dateRange[1]);
    super.onReady();
  }

  //选中两个日期后，查询指定范围内的日记
  Future<void> getMoodAndWeatherByRange(DateTime start, DateTime end) async {
    clearResult();
    state.finished = false;
    update();
    state.moodList = await IsarUtil.getMoodByDateRange(
        start, end.subtract(const Duration(days: -1)));

    final weatherList = await IsarUtil.getWeatherByDateRange(
        start, end.subtract(const Duration(days: -1)));
    for (final weather in weatherList) {
      if (weather.isNotEmpty) {
        state.weatherList.add(weather.first);
      }
    }
    state.moodMap = ArrayUtil.countList(state.moodList);
    state.weatherMap = ArrayUtil.countList(state.weatherList);
    state.finished = true;
    update();
  }

  void clearResult() {
    state.moodList.clear();
    state.weatherList.clear();
    state.moodMap.clear();
    state.weatherMap.clear();
    state.reply = '';
  }

  Future<void> openDatePicker(context) async {
    final result = await showCalendarDatePicker2Dialog(
        context: context,
        config: CalendarDatePicker2WithActionButtonsConfig(
          calendarViewMode: CalendarDatePicker2Mode.day,
          calendarType: CalendarDatePicker2Type.range,
          selectableDayPredicate: (date) => date.isBefore(DateTime.now()),
        ),
        dialogSize: const Size(325, 400),
        value: state.dateRange,
        borderRadius: BorderRadius.circular(20.0));
    if (result != null) {
      state.dateRange[0] = result[0]!;
      state.dateRange[1] = result[1]!;
      update();
      getMoodAndWeatherByRange(result[0]!, result[1]!);
    }
  }

  /// AI 分析：基于选定时间范围的日记内容做完整分析
  Future<void> getAi() async {
    final provider = AiProviderManager().currentProvider;
    if (provider == null) {
      NoticeUtil.showToast('请先在实验室配置 AI 服务商');
      return;
    }

    state.reply = '';
    update();

    try {
      // 1. 获取选定时间范围内的日记数据
      final diaryResult = await AiFunctionSystem.execute('getDiaryByDateRange', {
        'startDate': _fmt(state.dateRange[0]),
        'endDate': _fmt(state.dateRange[1]),
      });

      // 2. 构建分析提示词
      final moodSummary = state.moodMap.entries
          .map((e) => '心情 ${e.key}: ${e.value} 次')
          .join('\n');

      final systemPrompt = '''
你是一个专业的日记分析助手。分析用户指定时间范围内的日记数据，给出有深度的洞察。

分析维度：
1. 整体情绪趋势 — 情绪是平稳、波动、向好还是需要关注
2. 关注主题 — 日记中反复出现的主题是什么
3. 潜在问题 — 有没有需要注意的模式（如连续低落的情绪、睡眠问题、压力等）
4. 亮点发现 — 这段时间的积极变化或值得肯定的地方
5. 建议 — 基于数据给出的可操作建议

格式：分 3-4 段输出，每段不要太长。语气温暖专业，不要过于冷冰冰的数据分析。
''';

      final userMsg = '''
分析时间范围：${_fmt(state.dateRange[0])} 至 ${_fmt(state.dateRange[1])}

${diaryResult?.summary ?? '暂无日记数据'}

情绪统计：
$moodSummary
''';

      // 3. 调用 AI
      final stream = await provider.chat(
        messages: [
          AIMessage(role: 'system', content: systemPrompt),
          AIMessage(role: 'user', content: userMsg),
        ],
      );

      await for (final chunk in stream) {
        state.reply += chunk;
        update();
      }
    } catch (e) {
      print('[Analyse AI Error] $e');
      NoticeUtil.showToast('分析失败: $e');
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
