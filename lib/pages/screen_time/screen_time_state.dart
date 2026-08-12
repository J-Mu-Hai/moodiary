import 'package:moodiary/common/models/isar/usage_record.dart';

class ScreenTimeState {
  // 选中的日期（当天零点）
  late DateTime selectedDate;

  // 该日期的使用记录（按时长降序）
  late List<UsageRecord> records;

  // 是否已授予"使用情况访问"权限（Android）
  late bool granted;

  // 加载中
  late bool loading;

  // 最近 7 天的日期（日期 chip 行）
  late List<DateTime> recentDays;

  ScreenTimeState() {
    final now = DateTime.now();
    granted = false;
    loading = true;
    records = [];
    recentDays = [];
    selectedDate = DateTime(now.year, now.month, now.day);
  }
}
