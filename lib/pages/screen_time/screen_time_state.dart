import 'package:moodiary/common/models/isar/usage_record.dart';
import 'package:moodiary/common/models/isar/usage_session.dart';

/// 使用时间页的两种视图
enum UsageViewMode {
  /// 总览：当日总时长 + 各应用时长分布
  overview,

  /// 时间线：按时间段还原"什么时间段用了什么应用"
  timeline,
}

class ScreenTimeState {
  // 选中的日期（当天零点）
  late DateTime selectedDate;

  // 该日期的使用记录（按时长降序）
  late List<UsageRecord> records;

  // 该日期的使用会话（按开始时刻升序 = 时间线）
  late List<UsageSession> sessions;

  // 当前视图（总览 / 时间线）
  late UsageViewMode viewMode;

  // 持续监督开关状态（开启后原生前台服务 + 分钟级轮询）
  late bool monitoringEnabled;

  // 切换监督开关时短暂置位，防止连点
  late bool monitorBusy;

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
    sessions = [];
    recentDays = [];
    viewMode = UsageViewMode.overview;
    monitoringEnabled = false;
    monitorBusy = false;
    selectedDate = DateTime(now.year, now.month, now.day);
  }
}
