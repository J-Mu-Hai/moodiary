import 'dart:convert';

import 'package:moodiary/common/models/isar/category.dart';
import 'package:moodiary/presentation/isar.dart';

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
      summary = '近期的日记：\n' + lines.join('\n');
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
}
