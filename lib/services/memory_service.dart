import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/services/ai_prompt_manager.dart';
import 'package:moodiary/utils/session_merger.dart';

/// 画像类别清单（9 类，全部常驻）。
///
/// 结构上画像永远包含这 9 个槽位（哪怕某类暂时为空），
/// 保证"基础认知 / 沟通相关 / 行为规律"等维度的位置始终存在，
/// 不会被 AI 沉淀的偏好带偏。类别 key 用中文，与 AI 输出 `[类别]` 前缀一致。
const List<String> profileCategories = [
  '基础认知',
  '生活习惯',
  '情绪状态',
  '偏好与习惯',
  '目标与痛点',
  '人际关系',
  '行为规律',
  '梦想与理想',
  '行为逻辑',
];

/// 来源标签（供展示与 prompt）
String profileSourceLabel(String source) {
  switch (source) {
    case 'explicit':
      return '明确告知';
    case 'interaction':
      return '对话互动';
    case 'diary_analysis':
      return '日记分析';
    case 'pattern_recognition':
      return '行为规律';
    case 'legacy':
      return '历史沉淀';
    default:
      return source;
  }
}

/// 单条画像认知。
///
/// 每条都带 [confidence]（置信度，决定智能体说话的语气：1.0 确定地说、
/// 0.5 试探性地说）与 [source]（来源，决定可信度优先级：
/// explicit > diary_analysis > pattern_recognition）。
class ProfileEntry {
  /// 类别（[profileCategories] 之一）
  final String category;

  /// 要点内容（不含 `[类别]` 前缀）
  final String content;

  /// 置信度 0-1
  final double confidence;

  /// 来源：explicit | interaction | diary_analysis | pattern_recognition | legacy
  final String source;

  /// 首次沉淀时间
  final DateTime createdAt;

  /// 最近一次被验证/复现时间（语义覆盖时刷新）
  final DateTime lastConfirmedAt;

  ProfileEntry({
    required this.category,
    required this.content,
    required this.confidence,
    required this.source,
    required this.createdAt,
    DateTime? lastConfirmedAt,
  }) : lastConfirmedAt = lastConfirmedAt ?? createdAt;

  ProfileEntry copyWith({
    String? category,
    String? content,
    double? confidence,
    String? source,
    DateTime? lastConfirmedAt,
  }) =>
      ProfileEntry(
        category: category ?? this.category,
        content: content ?? this.content,
        confidence: confidence ?? this.confidence,
        source: source ?? this.source,
        createdAt: createdAt,
        lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
      );

  Map<String, dynamic> toJson() => {
        'category': category,
        'content': content,
        'confidence': confidence,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'lastConfirmedAt': lastConfirmedAt.toIso8601String(),
      };

  factory ProfileEntry.fromJson(Map<String, dynamic> json) => ProfileEntry(
        category: json['category']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.6,
        source: json['source']?.toString() ?? 'legacy',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
        lastConfirmedAt:
            DateTime.tryParse(json['lastConfirmedAt']?.toString() ?? '') ??
                DateTime.now(),
      );
}

/// 用户画像数据（长期认知）。
///
/// 画像 = 一组带类别/置信度/来源的 [ProfileEntry] + 沉淀版本历史。
/// 由 [MemoryService.consolidate] 每晚调用模型从当天素材中提炼、
/// 与旧画像合并后写回。
///
/// 存储用 PrefUtil（SharedPreferences）的 JSON blob：画像体量小（几十条要点），
/// 无需引入新 Isar 集合；接口稳定后如需类型安全/跨端同步，可平滑迁移到 Isar。
class UserMemoryData {
  /// 画像版本号（每次沉淀 +1）
  int profileVersion;

  /// 上次沉淀时间
  DateTime updatedAt;

  /// 画像要点（结构化，每条带类别/置信度/来源）
  List<ProfileEntry> entries;

  /// 历次沉淀的原始总结（溯源用，保留最近 [MemoryService.maxRawSummaries] 条）
  List<String> rawSummaries;

  UserMemoryData({
    this.profileVersion = 0,
    required this.updatedAt,
    this.entries = const [],
    this.rawSummaries = const [],
  });

  /// 9 类常驻视图：类别 → 该类别下的条目（空类别也有槽位，值为空列表）。
  Map<String, List<ProfileEntry>> get categories {
    final m = <String, List<ProfileEntry>>{};
    for (final c in profileCategories) {
      m[c] = [];
    }
    for (final e in entries) {
      (m[e.category] ??= []).add(e);
    }
    return m;
  }

  /// 兼容旧消费者：扁平化成 `[类别] 内容` 字符串列表。
  List<String> get aspects =>
      entries.map((e) => '[${e.category}] ${e.content}').toList();

  bool get isEmpty => entries.isEmpty;

  /// 全部认知条数
  int get totalCount => entries.length;

  Map<String, dynamic> toJson() => {
        'profileVersion': profileVersion,
        'updatedAt': updatedAt.toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'rawSummaries': rawSummaries,
      };

  /// 兼容旧存储格式：无 `entries` 字段时，从旧的 `aspects: ["[类别] 内容"]` 迁移，
  /// 迁移条目置信度取 0.6、来源记 `legacy`。
  factory UserMemoryData.fromJson(Map<String, dynamic> json) {
    final updatedAt =
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now();
    List<ProfileEntry> entries;
    final raw = json['entries'];
    if (raw is List) {
      entries = raw
          .whereType<Map>()
          .map((m) {
            try {
              return ProfileEntry.fromJson(Map<String, dynamic>.from(m));
            } catch (_) {
              return null;
            }
          })
          .whereType<ProfileEntry>()
          .toList();
    } else {
      // 旧格式迁移
      final oldAspects =
          (json['aspects'] as List?)?.whereType<String>() ?? const [];
      entries = oldAspects
          .map((a) {
            final catMatch = RegExp(r'^\[([^\]]+)\]').firstMatch(a);
            if (catMatch == null) return null;
            final cat = catMatch.group(1)!;
            final content = a.substring(catMatch.end).trimLeft();
            if (content.isEmpty) return null;
            return ProfileEntry(
              category: cat,
              content: content,
              confidence: 0.6,
              source: 'legacy',
              createdAt: updatedAt,
            );
          })
          .whereType<ProfileEntry>()
          .toList();
    }
    return UserMemoryData(
      profileVersion: json['profileVersion'] as int? ?? 0,
      updatedAt: updatedAt,
      entries: entries,
      rawSummaries: (json['rawSummaries'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// 长期记忆服务 — 用户认知画像的存取与沉淀。
///
/// 这是智能体「认识用户」的根基：
/// - [getProfile]：把画像拼成文本（带置信度/来源），注入对话/触发生成，
///   让智能体带着记忆说话、并能按置信度调整语气；
/// - [consolidate]：每晚回顾当天日记，让模型总结新认知并合并进画像。
class MemoryService {
  static const String _prefKey = 'userMemory';

  /// 画像要点上限（防止无限膨胀；超出时保留最新）
  static const int maxAspects = 40;

  /// 保留的原始沉淀总结条数
  static const int maxRawSummaries = 10;

  MemoryService._();

  /// 读取当前画像（无则返回空画像，结构上仍含全部 9 类槽位）
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

  /// 画像文本（供注入）。带置信度/来源，让智能体按确定程度说话；
  /// 无画像时返回空字符串。
  static Future<String> getProfile() async {
    final data = await load();
    if (data.entries.isEmpty) return '';
    return data.entries.map((e) {
      return '- [${e.category}] ${e.content}'
          '（置信 ${e.confidence.toStringAsFixed(1)} · '
          '${profileSourceLabel(e.source)}）';
    }).join('\n');
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

    // 3. 组装 prompt（当前画像带行号，remove 按行号引用，保证可溯）
    final base = await AiPromptManager().loadPrompt('memory_consolidate.txt');
    final profileText = current.entries.isEmpty
        ? '（暂无，从零开始）'
        : current.entries.asMap().entries.map((e) {
            final v = e.value;
            return '${e.key}: [${v.category}] ${v.content}'
                '（置信 ${v.confidence.toStringAsFixed(1)}）';
          }).join('\n');
    final system = StringBuffer()
      ..writeln(base)
      ..writeln()
      ..writeln('【当前画像】（行号从 0 开始，remove 按此引用）')
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
    final data = await mergeEntries(parsed.add, removes: parsed.removeIndexes);

    // 5. 附加本次原始总结（溯源，保留最近 maxRawSummaries 条）
    final rawSummaries = [...data.rawSummaries, raw];
    if (rawSummaries.length > maxRawSummaries) {
      rawSummaries.removeRange(0, rawSummaries.length - maxRawSummaries);
    }
    await save(UserMemoryData(
      profileVersion: data.profileVersion,
      updatedAt: data.updatedAt,
      entries: data.entries,
      rawSummaries: rawSummaries,
    ));

    return '画像沉淀完成：新增 ${parsed.add.length} 条，移除 ${parsed.removeIndexes.length} 条（共 ${data.totalCount} 条）';
  }

  /// 合并新认知进画像并写回（consolidate / ingestChatInsight 等共用核心）。
  ///
  /// [adds] 为结构化的新认知（带类别/置信度/来源）；[removes] 为旧画像中
  /// 被覆盖的索引（与当前 entries 顺序一致）。语义去重（同类别关键词重叠覆盖，
  /// 保留更高置信度）、裁剪到 [maxAspects] 条后保存，返回合并后的画像数据。
  static Future<UserMemoryData> mergeEntries(
    List<ProfileEntry> adds, {
    List<int> removes = const [],
  }) async {
    final current = await load();
    var entries = List<ProfileEntry>.from(current.entries);
    for (final idx in removes.toSet().toList()..sort()) {
      if (idx >= 0 && idx < entries.length) {
        entries.removeAt(idx);
      }
    }
    for (final add in adds) {
      if (add.category.isEmpty || add.content.trim().isEmpty) continue;
      final dup = _similarIndex(entries, add);
      if (dup != -1) {
        // 语义重复 → 新表述覆盖，置信度取更高，来源保留新来源，刷新确认时间
        final old = entries[dup];
        entries[dup] = add.copyWith(
          confidence: old.confidence > add.confidence
              ? old.confidence
              : add.confidence,
          lastConfirmedAt: DateTime.now(),
        );
      } else {
        entries.add(add);
      }
    }
    if (entries.length > maxAspects) {
      entries = entries.sublist(entries.length - maxAspects);
    }
    final data = UserMemoryData(
      profileVersion: current.profileVersion + 1,
      updatedAt: DateTime.now(),
      entries: entries,
      rawSummaries: current.rawSummaries,
    );
    await save(data);
    return data;
  }

  /// 合并「`[类别] 内容` 字符串」进画像（旧式/简单调用方用）。
  ///
  /// 每个字符串解析出类别与内容，带 [source] 来源与默认置信度；
  /// 无 `[类别]` 前缀的条目会被忽略（保证画像类别干净）。
  static Future<UserMemoryData> mergeAspects(
    List<String> adds, {
    List<int> removes = const [],
    String source = 'diary_analysis',
    double defaultConfidence = 0.7,
  }) async {
    final entries = adds
        .map((a) => _parseAspectString(a, source, defaultConfidence))
        .whereType<ProfileEntry>()
        .toList();
    return mergeEntries(entries, removes: removes);
  }

  /// 解析 `[类别] 内容` 字符串为结构化条目（非法类别/空内容返回 null）。
  static ProfileEntry? _parseAspectString(
      String s, String source, double defaultConfidence) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final catMatch = RegExp(r'^\[([^\]]+)\]').firstMatch(t);
    if (catMatch == null) return null;
    final cat = catMatch.group(1)!;
    if (!profileCategories.contains(cat)) return null;
    final content = t.substring(catMatch.end).trimLeft();
    if (content.isEmpty) return null;
    return ProfileEntry(
      category: cat,
      content: content,
      confidence: defaultConfidence,
      source: source,
      createdAt: DateTime.now(),
    );
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
从这段回答里提取可沉淀为长期画像的要点（姓名/年龄/身份/梦想/偏好/习惯等），
只输出严格 JSON（不要其他内容）：
{"add":[{"category":"类别","content":"要点","confidence":0.0-1.0}],"remove":[]}
- category 只能从 [基础认知][生活习惯][情绪状态][偏好与习惯][目标与痛点][人际关系][行为规律][梦想与理想][行为逻辑] 中选择
- confidence：用户明确告知（姓名/年龄/身份等）→ 0.9-1.0；只是提到/推断 → 0.5-0.7
- 来源固定为 interaction（对话互动），不需要写
- 要点要精炼具体，不确定的信息不要臆断''';
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
      final data = await mergeEntries(parsed.add, removes: parsed.removeIndexes);
      return parsed.add.isEmpty
          ? '未提炼到新画像要点（共 ${data.totalCount} 条）'
          : '已沉淀 ${parsed.add.length} 条：${parsed.add.map((e) => '[${e.category}] ${e.content}').join('；')}（共 ${data.totalCount} 条）';
    } catch (e) {
      print('[Memory] 问答沉淀失败: $e');
      return '问答沉淀失败: $e';
    }
  }

  /// 解析模型输出的增量 JSON。
  ///
  /// 富格式：`{"add":[{"category","content","confidence","source"}],"remove":[]}`
  /// 兼容旧格式：`{"add":["[类别] 内容",...],"remove":[]}`
  /// 解析失败时退回「逐行提取 `[类别]` 开头」。
  static ({List<ProfileEntry> add, List<int> removeIndexes}) _parseConsolidation(
      String raw) {
    final add = <ProfileEntry>[];
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
          for (final v in (m['add'] as List)) {
            if (v is Map) {
              final cat = v['category']?.toString() ?? '';
              final content = v['content']?.toString() ?? '';
              if (cat.isNotEmpty &&
                  content.isNotEmpty &&
                  profileCategories.contains(cat)) {
                final conf = (v['confidence'] is num)
                    ? ((v['confidence'] as num).toDouble()).clamp(0.0, 1.0)
                    : 0.7;
                final src = v['source']?.toString() ?? 'diary_analysis';
                add.add(ProfileEntry(
                  category: cat,
                  content: content,
                  confidence: conf,
                  source: src,
                  createdAt: DateTime.now(),
                ));
              }
            } else if (v is String) {
              final e = _parseAspectString(v, 'diary_analysis', 0.7);
              if (e != null) add.add(e);
            }
          }
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
      if (lineRe.hasMatch(l)) {
        final e = _parseAspectString(l, 'diary_analysis', 0.7);
        if (e != null) add.add(e);
      }
    }
    return (add: add, removeIndexes: remove);
  }

  /// 找与新认知语义重复的旧认知索引（同类别且内容有重叠关键词），否则 -1。
  static int _similarIndex(List<ProfileEntry> entries, ProfileEntry candidate) {
    final candWords = _keywords(candidate.content);

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.category != candidate.category) continue;
      final words = _keywords(e.content);
      final overlap = candWords.where((w) => words.contains(w)).length;
      if (overlap >= 2) return i;
    }
    return -1;
  }

  /// 提取内容关键词（去 [类别] 前缀与常见停用词，取 2 字以上词）
  static Set<String> _keywords(String content) {
    final words = content
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
