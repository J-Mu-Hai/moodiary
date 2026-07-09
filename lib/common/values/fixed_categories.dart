/// Moodsonder 固定分类
/// 这些分类由系统预置，不可删除、不可重命名
class FixedCategories {
  static const List<String> names = [
    '任务管理',
    '日记',
    '每日计划',
    '觉醒时刻',
  ];

  /// 判断分类名称是否为固定分类
  static bool isFixed(String categoryName) {
    return names.contains(categoryName);
  }
}
