import 'dart:convert';

import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/task_doc_parser.dart';

/// 统一作息库 — 按天记录起床时间、三时段计划、完成情况、每日计划栏目快照。
///
/// PrefUtil JSON 侧表（key=dailyRhythm）：{days: {"yyyy-M-d": DayRecord}}，
/// 保留最近 7 天。随 _metaKeys 快同步到电脑端（分析用）。
///
/// DayRecord:
/// ```json
/// { "wakeTime": "07:32", "wakeNote": ""|"熬夜",
///   "periods": { "morning": {"plan": "背50个单词", "done": false|true|null},
///                "noon": {"plan": "", "done": null},
///                "evening": {"plan": "", "done": null} },
///   "board": [ {"title": "写周报", "done": true, "source": "每日计划"} ] }
/// ```
class DailyRhythmStore {
  static const String _prefKey = 'dailyRhythm';

  /// 时段 key（与询问时机对应：<12 上午 / 12-14 中午 / 18-19 晚上 /
  /// 20-21 明天计划）。morning/noon/evening 是当天计划，tomorrow 是展望。
  static const List<String> periods = ['morning', 'noon', 'evening', 'tomorrow'];
  static const Map<String, String> periodLabels = {
    'morning': '上午',
    'noon': '中午',
    'evening': '晚上',
    'tomorrow': '明天',
  };

  static String _ymd(DateTime t) => '${t.year}-${t.month}-${t.day}';

  static Map<String, dynamic> _blankDay() => {
        'wakeTime': '',
        'wakeNote': '',
        'periods': {
          for (final p in periods)
            p: <String, dynamic>{'plan': '', 'done': null},
        },
        'board': <dynamic>[],
      };

  static Future<Map<String, dynamic>> _loadDays() async {
    final s = PrefUtil.getValue<String>(_prefKey);
    if (s == null || s.isEmpty) return {};
    try {
      final m = jsonDecode(s) as Map;
      final days = m['days'];
      if (days is Map) {
        return days.map((k, v) => MapEntry(k.toString(), v));
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveDays(Map<String, dynamic> days) async {
    // 裁剪：只保留最近 7 天
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    days.removeWhere((k, v) {
      final d = DateTime.tryParse(k);
      return d != null && d.isBefore(cutoff);
    });
    await PrefUtil.setValue<String>(_prefKey, jsonEncode({'days': days}));
  }

  /// 今天的记录（不存在则初始化）。返回可变 map，改完调 [_saveToday]。
  static Future<Map<String, dynamic>> today() async {
    final days = await _loadDays();
    final key = _ymd(DateTime.now());
    var day = days[key];
    if (day is! Map) {
      day = _blankDay();
      days[key] = day;
      await _saveDays(days);
    }
    return Map<String, dynamic>.from(day);
  }

  static Future<void> _saveToday(Map<String, dynamic> day) async {
    final days = await _loadDays();
    days[_ymd(DateTime.now())] = day;
    await _saveDays(days);
  }

  /// 读某一天的记录（可空）。
  static Future<Map<String, dynamic>?> dayOn(DateTime t) async {
    final days = await _loadDays();
    final day = days[_ymd(t)];
    if (day is! Map) return null;
    return Map<String, dynamic>.from(day);
  }

  static Map<String, Map<String, dynamic>> _periodsOf(
      Map<String, dynamic> day) {
    final m = day['periods'];
    if (m is! Map) return {};
    final out = <String, Map<String, dynamic>>{};
    m.forEach((k, v) {
      if (v is Map) out[k.toString()] = Map<String, dynamic>.from(v);
    });
    return out;
  }

  /// 记录当天首次用机（起床）。已有记录不覆盖；<5:00 打熬夜标。
  static Future<void> recordWake(DateTime t) async {
    final day = await today();
    if ((day['wakeTime']?.toString().isNotEmpty ?? false)) return;
    day['wakeTime'] =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (t.hour < 5) day['wakeNote'] = '熬夜';
    await _saveToday(day);
  }

  /// 存某一时段的计划内容（回答"上午打算做什么"类询问时调用）。
  static Future<void> setPeriodPlan(String period, String plan) async {
    final day = await today();
    final ps = _periodsOf(day);
    final p = ps.containsKey(period) ? ps[period]! : <String, dynamic>{};
    p['plan'] = plan.trim();
    // 计划更新后清掉旧的完成标记，完成情况等傍晚/复盘重新确认
    p['done'] = null;
    day['periods'] = ps;
    await _saveToday(day);
  }

  /// 标记某一时段计划完成/未完成（对话确认"做完了/还没"时调用）。
  static Future<void> markPeriodDone(String period, bool done) async {
    final day = await today();
    final ps = _periodsOf(day);
    final p = ps.containsKey(period) ? ps[period]! : <String, dynamic>{};
    p['done'] = done;
    day['periods'] = ps;
    await _saveToday(day);
  }

  /// 刷新今天「每日计划/任务管理」栏目快照（供决策与复盘）。
  ///
  /// 完成态判定：tag 含「完成」或 markdown 勾选框 `- [x]`（复用 TaskDocParser）。
  static Future<void> refreshBoard() async {
    try {
      final day = await today();
      final items = <Map<String, dynamic>>[];
      final cats = await IsarUtil.getAllCategoryAsync();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      for (final cat in cats) {
        if (cat.categoryName != '每日计划' && cat.categoryName != '任务管理') {
          continue;
        }
        final diaries = await IsarUtil.getDiariesByDateRange(
            start, start.add(const Duration(hours: 23, minutes: 59)));
        for (final d in diaries) {
          if (!d.show || d.categoryId != cat.id) continue;
          final doneByTag = d.tags.contains('完成');
          final doc = TaskDocParser.parse(d.content);
          if (doc.tasks.isNotEmpty) {
            for (final t in doc.tasks) {
              items.add({
                'title': t.text,
                'done': t.checked,
                'source': cat.categoryName,
              });
            }
          } else {
            items.add({
              'title': d.title.isNotEmpty ? d.title : '(今日计划)',
              'done': doneByTag,
              'source': cat.categoryName,
            });
          }
        }
      }
      day['board'] = items;
      await _saveToday(day);
    } catch (e) {
      print('[DailyRhythm] refreshBoard 失败: $e');
    }
  }

  /// 注入大脑决策上下文的自然语言摘要（【今日作息与计划】块）。
  ///
  /// 未收集的时段明确标"（未收集）"，让大脑知道今天的计划还有缺口，
  /// 也呼应"空缺并入晚上 11 点复盘"。
  static Future<String> summaryText() async {
    try {
      final day = await today();
      final buf = StringBuffer();
      final wake = day['wakeTime']?.toString() ?? '';
      final wakeNote = day['wakeNote']?.toString() ?? '';
      if (wake.isNotEmpty) {
        buf.writeln(
            '起床时间：$wake${wakeNote == '熬夜' ? '（熬夜）' : ''}');
      }
      final ps = _periodsOf(day);
      for (final p in periods) {
        final label = periodLabels[p]!;
        final plan = ps[p]?['plan']?.toString() ?? '';
        final done = ps[p]?['done'];
        if (p == 'tomorrow') {
          // 明天的计划白天不刷存在感：未收集时不显示，收集后才让大脑知道
          if (plan.isEmpty) continue;
          buf.writeln('$label计划：$plan');
          continue;
        }
        if (plan.isEmpty) {
          buf.writeln('$label计划：（未收集）');
        } else if (done == true) {
          buf.writeln('$label计划：$plan · 已完成');
        } else if (done == false) {
          buf.writeln('$label计划：$plan · 未完成');
        } else {
          buf.writeln('$label计划：$plan · 未确认完成');
        }
      }
      final board = day['board'];
      if (board is List && board.isNotEmpty) {
        final doneCount =
            board.where((b) => b is Map && b['done'] == true).length;
        final lines = board
            .take(10)
            .map((b) => b is Map
                ? '${b['done'] == true ? '✓' : '·'} ${b['title']}'
                : '')
            .where((s) => s.isNotEmpty)
            .join('、');
        buf.writeln(
            '今日任务清单（每日计划/任务管理）：$lines（$doneCount/${board.length} 完成）');
      }
      // 昨日完成情况对比
      final yesterday = await dayOn(
          DateTime.now().subtract(const Duration(days: 1)));
      if (yesterday != null) {
        final yp = _periodsOf(yesterday);
        final doneN =
            periods.where((p) => yp[p]?['done'] == true).length;
        final confN = periods.where((p) => yp[p]?['done'] is bool).length;
        if (confN > 0) {
          buf.writeln('昨日完成情况：$doneN/$confN 确认完成');
        }
      }
      return buf.toString().trim();
    } catch (e) {
      print('[DailyRhythm] summaryText 失败: $e');
      return '';
    }
  }

  /// 返回某一时段（如 'morning'）的中文名；未知返回原串。
  static String labelOf(String? period) => periodLabels[period] ?? period ?? '';
}
