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

  // 最近一次成功加载本地数据的时间（UI 展示数据新鲜度）
  DateTime? loadedAt;

  // 本地查询错误（静默处理，仅用于诊断，不打扰用户）
  String? lastError;

  ScreenTimeState() {
    final now = DateTime.now();
    granted = false;
    loading = true;
    records = [];
    recentDays = [];
    selectedDate = DateTime(now.year, now.month, now.day);
  }
}
