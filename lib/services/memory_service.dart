import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';
import 'package:moodiary/utils/session_merger.dart';

/// 用户画像数据（长期认知）。
///
/// 画像 = 一组「[类别] 要点」字符串 + 沉淀版本历史。由 [MemoryService.consolidate]
/// 每晚调用模型从当天素材中提炼、与旧画像合并后写回。
///
/// 存储用 PrefUtil（SharedPreferences）的 JSON blob：画像体量小（几十条要点），
/// 无需引入新 Isar 集合；接口稳定后如需类型安全/跨端同步，可平滑迁移到 Isar。
class UserMemoryData {
  /// 画像版本号（每次沉淀 +1）
  int profileVersion;

  /// 上次沉淀时间
  DateTime updatedAt;

  /// 画像要点，每条格式 `[类别] 内容`。
  /// 类别 ∈ {生活习惯, 情绪状态, 偏好与习惯, 目标与痛点, 人际关系, 行为规律}
  List<String> aspects;

  /// 历次沉淀的原始总结（溯源用，保留最近 [MemoryService.maxRawSummaries] 条）
  List<String> rawSummaries;

  UserMemoryData({
    this.profileVersion = 0,
    required this.updatedAt,
    this.aspects = const [],
    this.rawSummaries = const [],
  });

  Map<String, dynamic> toJson() => {
        'profileVersion': profileVersion,
        'updatedAt': updatedAt.toIso8601String(),
        'aspects': aspects,
        'rawSummaries': rawSummaries,
      };

  factory UserMemoryData.fromJson(Map<String, dynamic> json) => UserMemoryData(
        profileVersion: json['profileVersion'] as int? ?? 0,
        updatedAt:
            DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
        aspects: (json['aspects'] as List?)?.cast<String>() ?? [],
        rawSummaries: (json['rawSummaries'] as List?)?.cast<String>() ?? [],
      );
}

/// 长期记忆服务 — 用户认知画像的存取与沉淀。
///
/// 这是智能体「认识用户」的根基：
/// - [getProfile]：把画像拼成文本，注入对话/触发生成，让智能体带着记忆说话；
/// - [consolidate]：每晚回顾当天日记，让模型总结新认知并合并进画像。
class MemoryService {
  static const String _prefKey = 'userMemory';

  /// 画像要点上限（防止无限膨胀；超出时保留最新）
  static const int maxAspects = 40;

  /// 保留的原始沉淀总结条数
  static const int maxRawSummaries = 10;

  MemoryService._();

  /// 读取当前画像（无则返回空画像）
  static Future<UserMemoryData> load() async {
    final jsonStr = PrefUtil.getValue<String>(_prefKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return UserMemoryData(updatedAt: DateTime.now());
    }
    try {
      final m = jsonDecode(jsonStr) as Map<String, dynamic>;
      return UserMemoryData.fromJson(m);
    } catch (_) {
      return UserMemoryData(updatedAt: DateTime.now());
    }
  }

  static Future<void> save(UserMemoryData data) async {
    await PrefUtil.setValue<String>(_prefKey, jsonEncode(data.toJson()));
  }

  /// 画像文本（供注入）。无画像时返回空字符串。
  static Future<String> getProfile() async {
    final data = await load();
    if (data.aspects.isEmpty) return '';
    return data.aspects.map((a) => '- $a').join('\n');
  }

  /// 清空画像（测试/重置用）。
  static Future<void> clear() async {
    await PrefUtil.removeValue(_prefKey);
  }

  /// 每晚沉淀：回顾当天日记 → 模型总结新认知 → 合并写回。
  ///
  /// 返回本次沉淀的结果摘要（供日志/触发推送展示）。AI 未配置时返回原因。
  static Future<String> consolidate() async {
    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      return 'AI 未配置，跳过画像沉淀';
    }

    final current = await load();

    // 1. 收集当天素材（日记；行为时间线在阶段 2 接入）
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(hours: 23, minutes: 59));
    final diaries = await IsarUtil.getDiariesByDateRange(dayStart, dayEnd);

    final material = StringBuffer();
    if (diaries.isEmpty) {
      material.writeln('（今天没有写日记）');
    } else {
      for (final d in diaries) {
        final mood = ' 心情${(d.mood * 10).round()}/10';
        final title = d.title.isNotEmpty ? '《${d.title}》' : '(无标题)';
        final content = d.contentText.length > 200
            ? '${d.contentText.substring(0, 200)}…'
            : d.contentText;
        final tags = d.tags.isNotEmpty ? ' 标签:${d.tags.join(',')}' : '';
        material.writeln('[$title$mood$tags]');
        if (content.isNotEmpty) material.writeln(content);
        material.writeln('---');
      }
    }

    // 2. 行为时间线（阶段 2）：把今天的使用会话喂给模型，沉淀「行为规律」类画像。
    //    显示层先合并相邻同应用碎片，避免分钟级碎片误导模型。
    try {
      final sessions = await IsarUtil.getUsageSessionsByDay(
          '${now.year}/${now.month}/${now.day}');
      if (sessions.isNotEmpty) {
        material.writeln('\n【今天的使用时间线】（应用使用记录，用于提炼行为规律）');
        String fmtHM(DateTime t) =>
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        String fmtDur(int ms) {
          final m = (ms / 60000).round();
          if (m < 1) return '<1分钟';
          return m < 60 ? '$m分钟' : '${m ~/ 60}小时${m % 60}分钟';
        }

        for (final s in mergeAdjacentSessions(sessions)) {
          final end = s.isOpen ? '现在' : fmtHM(s.end!);
          final app = s.appName.isEmpty ? s.packageName : s.appName;
          material.writeln(
              '- ${fmtHM(s.start)}~$end $app（${fmtDur(s.durationMs)}）');
        }
        material
            .writeln('（数据可能不完整；行为规律只基于明显重复出现的情况，不确定不要臆断）');
      }
    } catch (_) {
      // 会话数据异常不影响沉淀主流程
    }

    // 3. 组装 prompt
    final base = await AiPromptManager().loadPrompt('memory_consolidate.txt');
    final profileText =
        current.aspects.isEmpty ? '（暂无，从零开始）' : current.aspects.join('\n');
    final system = StringBuffer()
      ..writeln(base)
      ..writeln()
      ..writeln('【当前画像】')
      ..writeln(profileText)
      ..writeln()
      ..writeln('【今天素材】')
      ..writeln(material);

    // 3. 调用模型
    final stream = await provider.chat(messages: [
      AIMessage(role: 'system', content: system.toString()),
      AIMessage(role: 'user', content: '请完成今天的画像沉淀。'),
    ]);
    final sb = StringBuffer();
    await for (final chunk in stream) {
      sb.write(chunk);
    }
    final raw = sb.toString().trim();
    if (raw.isEmpty) return '模型未返回内容，沉淀失败';

    // 4. 解析增量（add/remove）并合并写回
    final parsed = _parseConsolidation(raw);
    final data = await mergeAspects(parsed.add, removes: parsed.removeIndexes);

    // 5. 附加本次原始总结（溯源，保留最近 maxRawSummaries 条）
    final rawSummaries = [...data.rawSummaries, raw];
    if (rawSummaries.length > maxRawSummaries) {
      rawSummaries.removeRange(0, rawSummaries.length - maxRawSummaries);
    }
    await save(UserMemoryData(
      profileVersion: data.profileVersion,
      updatedAt: data.updatedAt,
      aspects: data.aspects,
      rawSummaries: rawSummaries,
    ));

    return '画像沉淀完成：新增 ${parsed.add.length} 条，移除 ${parsed.removeIndexes.length} 条（共 ${data.aspects.length} 条）';
  }

  /// 合并新要点进画像并写回（consolidate / ingestChatInsight / 日记分析共用）。
  ///
  /// [adds] 为新的 `[类别] 内容` 要点；[removes] 为旧画像中被覆盖的索引。
  /// 语义去重（同类别关键词重叠覆盖）、裁剪到 [maxAspects] 条后保存，
  /// 返回合并后的画像数据。
  static Future<UserMemoryData> mergeAspects(
    List<String> adds, {
    List<int> removes = const [],
  }) async {
    final current = await load();
    var aspects = List<String>.from(current.aspects);
    for (final idx in removes.toSet().toList()..sort()) {
      if (idx >= 0 && idx < aspects.length) {
        aspects.removeAt(idx);
      }
    }
    for (final add in adds) {
      final normalized = add.trim();
      if (normalized.isEmpty) continue;
      final dup = _similarIndex(aspects, normalized);
      if (dup != -1) {
        aspects[dup] = normalized; // 语义重复 → 用新表述覆盖
      } else {
        aspects.add(normalized);
      }
    }
    if (aspects.length > maxAspects) {
      aspects = aspects.sublist(aspects.length - maxAspects);
    }
    final data = UserMemoryData(
      profileVersion: current.profileVersion + 1,
      updatedAt: DateTime.now(),
      aspects: aspects,
      rawSummaries: current.rawSummaries,
    );
    await save(data);
    return data;
  }

  /// 从一次问答中提取画像要点并合并（「第一次沟通」问清姓名/年龄/身份后调用）。
  ///
  /// [question] 智能体问的问题；[answer] 用户的回答。返回沉淀摘要。
  static Future<String> ingestChatInsight(
      String question, String answer) async {
    final provider = AiProviderManager().currentProvider;
    if (provider == null || !provider.isConfigured) {
      return 'AI 未配置，无法提取画像';
    }
    final text = answer.trim();
    if (text.isEmpty) return '回答为空，未沉淀';
    final prompt = '''
用户被问到「$question」，回答：「$text」。
从这段回答里提取可沉淀为长期画像的要点（姓名/年龄/身份/梦想/偏好/习惯等），以 [类别] 要点格式。
只输出严格 JSON（不要其他内容）：{"add":["[类别] 要点1",...],"remove":[旧画像中被覆盖的索引，没有则空数组]}
类别只能从：[基础认知][生活习惯][情绪状态][偏好与习惯][目标与痛点][人际关系][行为规律][梦想与理想][行为逻辑] 中选择。
要点要精炼具体，不确定的信息不要臆断。''';
    try {
      final stream = await provider.chat(messages: [
        AIMessage(role: 'user', content: prompt),
      ]);
      final sb = StringBuffer();
      await for (final chunk in stream) {
        sb.write(chunk);
      }
      final raw = sb.toString().trim();
      if (raw.isEmpty) return '模型未返回内容';
      final parsed = _parseConsolidation(raw);
      final data =
          await mergeAspects(parsed.add, removes: parsed.removeIndexes);
      return parsed.add.isEmpty
          ? '未提炼到新画像要点（共 ${data.aspects.length} 条）'
          : '已沉淀 ${parsed.add.length} 条：${parsed.add.join('；')}（共 ${data.aspects.length} 条）';
    } catch (e) {
      print('[Memory] 问答沉淀失败: $e');
      return '问答沉淀失败: $e';
    }
  }

  /// 解析模型输出的 JSON 增量。
  /// 宽容处理 ```json 围栏与前后杂文；解析失败时退回「整段作为 add」。
  static ({List<String> add, List<int> removeIndexes}) _parseConsolidation(
      String raw) {
    final add = <String>[];
    final remove = <int>[];

    String text = raw.trim();
    text = text.replaceFirst(RegExp(r'^```(json)?\s*'), '').trim();
    text = text.replaceFirst(RegExp(r'\s*```$'), '').trim();

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final m = jsonDecode(text.substring(start, end + 1)) as Map;
        if (m['add'] is List) {
          add.addAll((m['add'] as List).whereType<String>());
        }
        if (m['remove'] is List) {
          for (final v in (m['remove'] as List)) {
            if (v is num) remove.add(v.toInt());
          }
        }
        return (add: add, removeIndexes: remove);
      } catch (_) {
        // fallthrough 到逐行解析
      }
    }

    // 退化：按行提取 "[类别]" 开头的内容作为新增
    final lineRe = RegExp(r'^\[[^\]]+\].+');
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (lineRe.hasMatch(l)) add.add(l);
    }
    return (add: add, removeIndexes: remove);
  }

  /// 找与新要点语义重复的旧要点索引（同类别且内容有重叠关键词），否则 -1。
  static int _similarIndex(List<String> aspects, String candidate) {
    final catMatch = RegExp(r'^\[([^\]]+)\]').firstMatch(candidate);
    if (catMatch == null) return -1;
    final cat = catMatch.group(1)!;
    final candWords = _keywords(candidate);

    for (var i = 0; i < aspects.length; i++) {
      final a = aspects[i];
      if (!a.startsWith('[$cat]')) continue;
      final words = _keywords(a);
      final overlap =
          candWords.where((w) => words.contains(w)).length;
      if (overlap >= 2) return i;
    }
    return -1;
  }

  /// 提取内容关键词（去 [类别] 前缀与常见停用词，取 2 字以上词）
  static Set<String> _keywords(String aspect) {
    final body = aspect.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
    final words = body
        .split(RegExp(r'[\s，。、；：,.!?！？()（）【】-]+'))
        .where((w) => w.length >= 2)
        .toSet();
    const stop = {
      '用户', '的人', '的时候', '总是', '经常', '喜欢', '通常', '习惯', '对于', '非常', '比较',
      '感觉', '有点', '可能', '应该', '今天', '每天', '一个', '这个', '那个', '自己',
    };
    return words.difference(stop);
  }
}
