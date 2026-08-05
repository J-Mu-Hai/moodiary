import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:moodiary/presentation/pref.dart';

/// 支出分类的预设列表
class ExpenseCategories {
  static const List<ExpenseCategory> defaults = [
    ExpenseCategory(icon: Icons.restaurant_rounded, name: '餐饮', color: 0xFFFF7043),
    ExpenseCategory(icon: Icons.directions_bus_rounded, name: '交通', color: 0xFF42A5F5),
    ExpenseCategory(icon: Icons.shopping_bag_rounded, name: '购物', color: 0xFFAB47BC),
    ExpenseCategory(icon: Icons.home_rounded, name: '住房', color: 0xFF26A69A),
    ExpenseCategory(icon: Icons.gamepad_rounded, name: '娱乐', color: 0xFFFFA726),
    ExpenseCategory(icon: Icons.local_hospital_rounded, name: '医疗', color: 0xFFEF5350),
    ExpenseCategory(icon: Icons.school_rounded, name: '教育', color: 0xFF5C6BC0),
    ExpenseCategory(icon: Icons.phone_android_rounded, name: '通讯', color: 0xFF78909C),
    ExpenseCategory(icon: Icons.more_horiz_rounded, name: '其他', color: 0xFF8D6E63),
  ];

  /// 从 SharedPreferences 加载自定义分类
  static List<ExpenseCategory> _loadCustom() {
    final json = PrefUtil.getValue<String>('customExpenseCategories');
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => ExpenseCategory.fromJson(e)).toList();
  }

  /// 保存自定义分类
  static Future<void> _saveCustom(List<ExpenseCategory> cats) async {
    final json = jsonEncode(cats.map((c) => c.toJson()).toList());
    await PrefUtil.setValue<String>('customExpenseCategories', json);
  }

  /// 获取所有分类
  static List<ExpenseCategory> get all => [...defaults, ..._loadCustom()];

  /// 添加自定义分类
  static Future<void> addCustom(ExpenseCategory cat) async {
    final custom = _loadCustom();
    custom.add(cat);
    await _saveCustom(custom);
  }

  /// 删除自定义分类
  static Future<void> removeCustom(String name) async {
    final custom = _loadCustom();
    custom.removeWhere((c) => c.name == name);
    await _saveCustom(custom);
  }
}

class ExpenseCategory {
  final IconData icon;
  final String name;
  final int color;

  const ExpenseCategory({
    required this.icon,
    required this.name,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'color': color,
        'iconCodePoint': icon.codePoint,
        'iconFontFamily': icon.fontFamily,
      };

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      name: json['name'] as String,
      color: json['color'] as int,
      icon: IconData(
        json['iconCodePoint'] as int,
        fontFamily: json['iconFontFamily'] as String?,
      ),
    );
  }
}
