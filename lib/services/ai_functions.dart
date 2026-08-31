import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/utils/environment_sensor.dart';
import 'package:moodiary/utils/session_merger.dart';
import 'package:moodiary/utils/tts_speaker.dart';

import 'agent_brain/behavior_model.dart';

/// AI 函数调用返回的封装
class AiFunctionResult {
  final String functionName;
  final dynamic data;
  final String summary;

  AiFunctionResult({
    required this.functionName,
    required this.data,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
        'function': functionName,
        'data': data,
        'summary': summary,
      };
}

/// 函数调用系统 — 查询各种数据供 AI 使用
class AiFunctionSystem {
  /// 执行指定函数
  static Future<AiFunctionResult?> execute(
      String name, Map<String, String> params) async {
    try {
      switch (name) {
        case 'getDiaryByDateRange':
          return await _getDiaryByDateRange(
              params['startDate'], params['endDate']);
        case 'getDiaryByCategory':
          return await _getDiaryByCategory(
              params['categoryName'], params['startDate'], params['endDate']);
        case 'getTodayPlan':
          return await _getTodayPlan(params['date']);
        case 'getTaskAnalysis':
          return await _getTaskAnalysis(params['date']);
        case 'getCategories':
          return await _getCategories();
        case 'getUniversalValues':
          return await _getUniversalValues(params['topic']);
        case 'env_snapshot':
          return await _getEnvSnapshot();
        case 'speak':
          return await _speak(params['text']);
        case 'get_usage_timeline':
          return await _getUsageTimeline(
              params['date'], params['startHour'], params['endHour']);
        case 'get_behavior_summary':
          return await _getBehaviorSummary(
              params['days'], params['windowMinutes']);
        case 'set_user_location':
          return await _setUserLocation(
              params['province'], params['city'], params['district']);
        default:
          return null;
      }
    } catch (e) {
      return AiFunctionResult(
        functionName: name,
        data: null,
        summary: '查询失败: $e',
      );
    }
  }

  /// 1. 按日期范围获取日记摘要
  static Future<AiFunctionResult> _getDiaryByDateRange(
      String? start, String? end) async {
    final startDate = start != null ? DateTime.parse(start) : DateTime.now().subtract(const Duration(days: 7));
    final endDate = end != null ? DateTime.parse(end) : DateTime.now();

    final diaries = await IsarUtil.getDiariesByDateRange(startDate, endDate);
    final list = diaries.map((d) => {
          'date': '${d.time.month}/${d.time.day}',
          'title': d.title,
          'mood': d.mood,
          'weather': d.weather.isNotEmpty ? d.weather.first : '',
          'tags': d.tags,
          'categoryId': d.categoryId,
          'snippet': d.contentText.length > 100
              ? d.contentText.substring(0, 100)
              : d.contentText,
        }).toList();

    // 生成自然语言摘要
    String summary;
    if (list.isEmpty) {
      summary = '最近几天没有写日记。';
    } else {
      final lines = list.map((d) {
        final mood = d['mood'] != null ? ' 心情${((d['mood'] as double) * 10).round()}/10' : '';
        final title = d['title'].toString();
        final snippet = d['snippet'].toString();
        return '[${d['date']}$mood] ${title.isNotEmpty ? title : '(无标题)'} — ${snippet.substring(0, snippet.length.clamp(0, 60))}';
      }).toList();
      summary = '近期的日记：\n${lines.join('\n')}';
    }

    return AiFunctionResult(
      functionName: 'getDiaryByDateRange',
      data: list,
      summary: summary,
    );
  }

  /// 2. 按分类获取日记
  static Future<AiFunctionResult> _getDiaryByCategory(
      String? categoryName, String? start, String? end) async {
    if (categoryName == null) {
      return AiFunctionResult(
        functionName: 'getDiaryByCategory',
        data: [],
        summary: '未指定分类',
      );
    }

    final allCategories = await IsarUtil.getAllCategoryAsync();
    final cat = allCategories.where((c) => c.categoryName == categoryName).firstOrNull;
    if (cat == null) {
      return AiFunctionResult(
        functionName: 'getDiaryByCategory',
        data: [],
        summary: '未找到分类: $categoryName',
      );
    }

    final startDate = start != null ? DateTime.parse(start) : DateTime.now().subtract(const Duration(days: 30));
    final endDate = end != null ? DateTime.parse(end) : DateTime.now();

    final diaries = await IsarUtil.getDiariesByDateRange(startDate, endDate);
    final filtered = diaries.where((d) => d.categoryId == cat.id).toList();

    final list = filtered.map((d) => {
          'date': '${d.time.month}/${d.time.day}',
          'title': d.title,
          'mood': d.mood,
          'content': d.contentText.length > 100
              ? d.contentText.substring(0, 100)
              : d.contentText,
          'tags': d.tags,
        }).toList();

    return AiFunctionResult(
      functionName: 'getDiaryByCategory',
      data: list,
      summary: '分类"$categoryName"下找到 ${list.length} 篇日记',
    );
  }

  /// 3. 获取今日计划
  static Future<AiFunctionResult> _getTodayPlan(String? dateStr) async {
    final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));

    final diaries = await IsarUtil.getDiariesByDateRange(dayStart, dayEnd);
    // 查找"每日计划"分类下的日记
    final cats = await IsarUtil.getAllCategoryAsync();
    final planCat = cats.where((c) => c.categoryName == '每日计划').firstOrNull;

    List<Map<String, dynamic>> plans = [];
    if (planCat != null) {
      plans = diaries
          .where((d) => d.categoryId == planCat.id)
          .map((d) => {
                'title': d.title,
                'content': d.contentText,
                'tags': d.tags,
              })
          .toList();
    }

    return AiFunctionResult(
      functionName: 'getTodayPlan',
      data: plans,
      summary: plans.isNotEmpty
          ? '今日有 ${plans.length} 条计划'
          : '今日没有计划',
    );
  }

  /// 4. 获取任务分析数据
  static Future<AiFunctionResult> _getTaskAnalysis(String? dateStr) async {
    final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));

    final diaries = await IsarUtil.getDiariesByDateRange(dayStart, dayEnd);
    final cats = await IsarUtil.getAllCategoryAsync();
    final taskCat = cats.where((c) => c.categoryName == '任务管理').firstOrNull;

    List<Map<String, dynamic>> tasks = [];
    if (taskCat != null) {
      tasks = diaries
          .where((d) => d.categoryId == taskCat.id)
          .map((d) => {
                'title': d.title,
                'completed': d.tags.contains('完成'), // 通过标签判定
                'content': d.contentText,
              })
          .toList();
    }

    return AiFunctionResult(
      functionName: 'getTaskAnalysis',
      data: {
        'totalTasks': tasks.length,
        'completedTasks': tasks.where((t) => t['completed'] == true).length,
        'pendingTasks': tasks.where((t) => t['completed'] != true).length,
        'details': tasks,
      },
      summary: '任务管理中有 ${tasks.length} 个任务',
    );
  }

  /// 5. 获取所有分类
  static Future<AiFunctionResult> _getCategories() async {
    final cats = await IsarUtil.getAllCategoryAsync();
    final list = cats.map((c) => {
          'name': c.categoryName,
          'id': c.id,
        }).toList();

    return AiFunctionResult(
      functionName: 'getCategories',
      data: list,
      summary: '共有 ${list.length} 个分类',
    );
  }

  /// 6. 获取通用价值观详细准则（按主题从 values_detail.md 检索）
  static Future<AiFunctionResult> _getUniversalValues(String? topic) async {
    try {
      final raw = await rootBundle.loadString('assets/ai/values_detail.md');
      final sections = _splitMarkdownSections(raw);

      if (sections.isEmpty) {
        return AiFunctionResult(
          functionName: 'getUniversalValues',
          data: null,
          summary: '通用价值观详细库当前为空。',
        );
      }

      // 按主题关键词匹配章节
      final matched = _matchValueSections(sections, topic);

      String summary;
      if (matched.isEmpty) {
        // 没匹配到，给出目录让 AI 换个主题词
        final titles = sections.map((s) => s.title).join('\n');
        summary = '未找到与"$topic"匹配的价值观主题。当前可用主题：\n$titles\n\n请用上面的主题名重新调用。';
      } else {
        final buf = StringBuffer();
        for (final s in matched) {
          buf.writeln('## ${s.title}');
          buf.writeln(s.content);
          buf.writeln();
        }
        summary = buf.toString();
      }

      // 截断防止上下文过长
      if (summary.length > 2000) {
        summary = '${summary.substring(0, 2000)}\n…(已截断，如需完整内容请换更具体的主题词)';
      }

      return AiFunctionResult(
        functionName: 'getUniversalValues',
        data: matched.map((s) => s.title).toList(),
        summary: summary,
      );
    } catch (e) {
      return AiFunctionResult(
        functionName: 'getUniversalValues',
        data: null,
        summary: '通用价值观详细库加载失败: $e',
      );
    }
  }

  /// 把 markdown 按 `## ` 章节切块
  static List<({String title, String content})> _splitMarkdownSections(String raw) {
    final sections = <({String title, String content})>[];
    String? currentTitle;
    final currentBody = <String>[];

    void flush() {
      if (currentTitle != null) {
        sections.add((
          title: currentTitle,
          content: currentBody.join('\n').trim(),
        ));
      }
    }

    for (final line in raw.split('\n')) {
      final m = RegExp(r'^##\s+(.+)').firstMatch(line);
      if (m != null) {
        flush();
        currentTitle = m.group(1)!.trim();
        currentBody.clear();
      } else if (currentTitle != null) {
        currentBody.add(line);
      }
    }
    flush();
    return sections;
  }

  /// 按主题关键词对章节打分：标题命中权重更高，返回最高分的前 1-2 个章节
  static List<({String title, String content})> _matchValueSections(
      List<({String title, String content})> sections, String? topic) {
    if (topic == null || topic.trim().isEmpty) {
      return sections.take(1).toList();
    }

    final keywords = topic
        .split(RegExp(r'[\s,，。；;、/：:（）()]+'))
        .where((k) => k.trim().isNotEmpty)
        .toList();

    final scored = sections.map((s) {
      final titleLower = s.title.toLowerCase();
      final bodyLower = s.content.toLowerCase();
      var score = 0;
      for (final kw in keywords) {
        final k = kw.toLowerCase();
        if (titleLower.contains(k)) {
          score += 3;
        } else if (bodyLower.contains(k)) {
          score += 1;
        }
      }
      return (section: s, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    final best = scored.where((e) => e.score > 0).toList();
    if (best.isEmpty) return const [];

    final top = best.first.score;
    return best
        .where((e) => e.score >= top)
        .take(2)
        .map((e) => e.section)
        .toList();
  }

  /// 7. 环境快照：用户当前城市 + 实时天气（IP 定位，零权限）
  static Future<AiFunctionResult> _getEnvSnapshot() async {
    final snap = await EnvironmentSensor.getSnapshot();
    if (snap == null) {
      return AiFunctionResult(
        functionName: 'env_snapshot',
        data: null,
        summary: '无法获取当前位置与天气（可能是网络或 key 配置问题）。',
      );
    }
    final p = snap['province'].toString();
    final c = snap['city'].toString();
    final d = snap['district'].toString();
    final city = '$p${(c.isNotEmpty && !p.contains(c) ? c : '')}$d';
    return AiFunctionResult(
      functionName: 'env_snapshot',
      data: snap,
      summary: '用户当前在$city，天气${snap['weather']}，${snap['temp']}℃，'
          '体感${snap['feelsLike']}℃，${snap['windDir']}。',
    );
  }

  /// 9. 语音朗读：把指定文本合成语音并播放
  static Future<AiFunctionResult> _speak(String? text) async {
    if (text == null || text.trim().isEmpty) {
      return AiFunctionResult(
        functionName: 'speak',
        data: null,
        summary: '未提供朗读文本。',
      );
    }
    final ok = await TtsSpeaker.speak(text);
    return AiFunctionResult(
      functionName: 'speak',
      data: {'ok': ok, 'text': text},
      summary: ok ? '已朗读：$text' : '语音朗读失败。',
    );
  }

  /// 10. 获取某天的应用使用时间线：按时间段列出用户用了哪些应用、各多久。
  ///
  /// 这是阶段 2「行为认知」的函数地基：喂给模型可还原用户一天的生活节奏
  /// （什么时间段在做什么、是否用手机）。参数 date 可选（默认今天），
  /// startHour/endHour 可选（0-23，过滤时段）。
  static Future<AiFunctionResult> _getUsageTimeline(
      String? dateStr, String? startHour, String? endHour) async {
    final date = (dateStr != null && dateStr.trim().isNotEmpty)
        ? DateTime.tryParse(dateStr) ?? DateTime.now()
        : DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final yMd = '${day.year}/${day.month}/${day.day}';

    final sessions = await IsarUtil.getUsageSessionsByDay(yMd);
    final fromH = int.tryParse(startHour ?? '');
    final toH = int.tryParse(endHour ?? '');
    var filtered = sessions;
    if (fromH != null) {
      filtered = filtered.where((s) => s.start.hour >= fromH).toList();
    }
    if (toH != null) {
      filtered = filtered.where((s) => (s.end ?? s.start).hour <= toH).toList();
    }

    // 显示层合并相邻同应用碎片（纯函数），还原"连续一段"的使用
    final merged = mergeAdjacentSessions(filtered);

    String fmtHM(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    String fmtDuration(int ms) {
      final minutes = (ms / 60000).round();
      if (minutes < 1) return '<1分钟';
      if (minutes < 60) return '$minutes分钟';
      return '${minutes ~/ 60}小时${minutes % 60}分钟';
    }

    final list = merged.map((s) {
      final end = s.isOpen ? null : fmtHM(s.end!);
      return {
        'start': fmtHM(s.start),
        'end': end,
        'app': s.appName.isEmpty ? s.packageName : s.appName,
        'durationMs': s.durationMs,
      };
    }).toList();

    String summary;
    if (list.isEmpty) {
      summary = '$yMd 没有使用时间线记录（持续监督未开启，或该日无手机使用数据）。';
    } else {
      final total = list.fold<int>(0, (sum, m) => sum + (m['durationMs'] as int));
      final lines = list.map((m) {
        final end = m['end'] ?? '现在';
        return '- ${m['start']}~$end ${m['app']}（${fmtDuration(m['durationMs'] as int)}）';
      }).join('\n');
      summary = '$yMd 的使用时间线（共约${fmtDuration(total)}）：\n$lines';
    }

    return AiFunctionResult(
      functionName: 'get_usage_timeline',
      data: list,
      summary: summary,
    );
  }

  /// 11. 获取智能体行为认知：近 N 天观察的分钟窗口聚合 + 一句话行为画像。
  ///
  /// 阶段 4「行为认知自主化」的工具面：让模型在对话里能查到「用户一天 24h
  /// 大致在做什么」的已归纳结论，与 get_usage_timeline（原始时间线）互补。
  static Future<AiFunctionResult> _getBehaviorSummary(
      String? daysStr, String? windowStr) async {
    final days = int.tryParse(daysStr ?? '') ?? 7;
    final window = int.tryParse(windowStr ?? '') ?? 120;
    final agg = await BehaviorModelStore.aggregationText(
        days: days, windowMinutes: window);
    final model = await BehaviorModelStore.load();
    final narrative = model == null || model.narrative.isEmpty
        ? '（尚未建模，将自动归纳）'
        : model.narrative;
    final current = await BehaviorModelStore.currentWindowText(DateTime.now(),
        days: days, windowMinutes: window);
    return AiFunctionResult(
      functionName: 'get_behavior_summary',
      data: {
        'narrative': model?.narrative ?? '',
        'updatedAt': model?.updatedAt.toIso8601String() ?? '',
        'windowMinutes': window,
        'days': days,
      },
      summary: '【智能体行为认知】\n'
          '近$days天手机观察（自动归纳）：\n$agg\n'
          '智能体归纳：$narrative\n'
          '当前对应时段：$current',
    );
  }

  /// 12. 修正用户所在地：写入地点覆盖，之后所有环境快照以它为准。
  ///
  /// IP 定位的行政区名不精确（海淀可能被识别成西城），当对话/信号里用户
  /// 明确说出所在地（如「我在北京海淀」），智能体调用本函数把省市区写进
  /// `locationOverride`，EnvironmentSensor 取快照时优先用覆盖值。
  /// province/city/district 均允许缺省——缺省的维度保持原样不覆盖。
  static Future<AiFunctionResult> _setUserLocation(String? province,
      String? city, String? district) async {
    final p = province?.trim() ?? '';
    final c = city?.trim() ?? '';
    final d = district?.trim() ?? '';
    if (p.isEmpty && c.isEmpty && d.isEmpty) {
      return AiFunctionResult(
        functionName: 'set_user_location',
        data: null,
        summary: '请提供至少一个地点信息（省/市/区）。',
      );
    }

    // 读旧覆盖值，缺省的维度沿用旧值（首次写入时沿用 IP 定位的近似值）
    final old = EnvironmentSensor.overrideValue;
    final merged = <String, String>{
      'province': p.isNotEmpty ? p : (old?['province'] ?? ''),
      'city': c.isNotEmpty ? c : (old?['city'] ?? ''),
      'district': d.isNotEmpty ? d : (old?['district'] ?? ''),
    };
    await PrefUtil.setValue<String>(
        'locationOverride', jsonEncode(merged));

    final place = '${merged['province']}${(merged['city']!.isNotEmpty && !merged['province']!.contains(merged['city']!) ? merged['city'] : '')}${merged['district']}';
    return AiFunctionResult(
      functionName: 'set_user_location',
      data: merged,
      summary: '已把用户所在地修正为「$place」，之后的地点判断以此为准。',
    );
  }
}
