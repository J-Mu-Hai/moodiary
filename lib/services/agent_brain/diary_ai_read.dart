import 'dart:convert';

import 'package:moodiary/common/models/isar/diary.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';

/// 日记「是否被 AI 读过」侧表。
///
/// isar_generator 在当前环境不可用，无法给 Isar `Diary` 模型加字段再 codegen，
/// 因此用与 `userMemory`/`agentTasks` 一致的 PrefUtil JSON blob 记录：
/// `key=diaryAiRead`，值为 `{diaryId: {"readAt": iso8601, "note": "摘要"}}`。
/// **不在表里的日记即「未读」**。接口稳定后可平滑迁移 Isar。
class DiaryAiReadStore {
  static const String _prefKey = 'diaryAiRead';

  /// 读取完整表（diaryId → 读取记录）。
  static Future<Map<String, Map<String, dynamic>>> load() async {
    final s = PrefUtil.getValue<String>(_prefKey);
    if (s == null || s.isEmpty) return {};
    try {
      return (jsonDecode(s) as Map)
          .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _save(Map<String, Map<String, dynamic>> map) async {
    await PrefUtil.setValue<String>(_prefKey, jsonEncode(map));
  }

  static Future<bool> isRead(String diaryId) async =>
      (await load()).containsKey(diaryId);

  /// 标记一篇日记为已读（带分析摘要 note）。
  static Future<void> markRead(String diaryId, {String note = ''}) async {
    final map = await load();
    map[diaryId] = {
      'readAt': DateTime.now().toIso8601String(),
      'note': note,
    };
    await _save(map);
  }

  /// 批量标记已读。
  static Future<void> markReadAll(
    Iterable<Diary> diaries, {
    String note = '',
  }) async {
    if (diaries.isEmpty) return;
    final map = await load();
    final now = DateTime.now().toIso8601String();
    for (final d in diaries) {
      map[d.id] = {'readAt': now, 'note': note};
    }
    await _save(map);
  }

  /// 查询未读日记：`[since]`（含）之后、不在已读表内、未进回收站，
  /// 按时间倒序取最近 `[limit]` 篇。
  static Future<List<Diary>> unreadDiaries({
    DateTime? since,
    int limit = 10,
  }) async {
    final read = await load();
    final now = DateTime.now();
    final start = since ?? DateTime(now.year, now.month, now.day - 3);
    final all = await IsarUtil.getDiariesByDateRange(start, now);
    final unread =
        all.where((d) => d.show && !read.containsKey(d.id)).toList();
    unread.sort((a, b) => b.time.compareTo(a.time));
    return unread.take(limit).toList();
  }

  /// 未读数量（`[since]` 起，用于信号描述）。
  static Future<int> unreadCount({DateTime? since}) async {
    final read = await load();
    final now = DateTime.now();
    final start = since ?? DateTime(now.year, now.month, now.day - 3);
    final all = await IsarUtil.getDiariesByDateRange(start, now);
    return all.where((d) => d.show && !read.containsKey(d.id)).length;
  }
}
