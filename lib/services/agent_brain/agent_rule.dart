import 'dart:convert';

import 'package:moodiary/presentation/pref.dart';

/// 用户自定义规则存储 — 用户把「想让它帮忙的事」写成自然语言规则，
/// 由大脑分析后转化为合理的任务规划（agent_rule 是大脑上下文的输入之一）。
///
/// 存储：PrefUtil `key=agentRules`，JSON list of String。
class AgentRuleStore {
  static const String _prefKey = 'agentRules';

  static Future<List<String>> load() async {
    final jsonStr = PrefUtil.getValue<String>(_prefKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List;
      return list.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<String> rules) async {
    await PrefUtil.setValue<String>(_prefKey, jsonEncode(rules));
  }

  static Future<void> add(String rule) async {
    final rules = await load();
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return;
    rules.add(trimmed);
    await _save(rules);
  }

  static Future<void> remove(String rule) async {
    final rules = await load();
    rules.remove(rule);
    await _save(rules);
  }
}
