import 'dart:async';
import 'dart:io';

import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/services/screen_time_service.dart';
import 'package:moodiary/utils/webdav_util.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:refreshed/refreshed.dart';

import 'screen_time_state.dart';

class ScreenTimeLogic extends GetxController {
  final ScreenTimeState state = ScreenTimeState();

  /// 与 Isar 的 yMd 索引一致的日期键，形如 `2026/8/8`
  static String dayKey(DateTime d) => '${d.year}/${d.month}/${d.day}';

  @override
  void onReady() async {
    super.onReady();
    state.monitoringEnabled = ScreenTimeService().monitoringEnabled;
    try {
      await reload();
    } catch (e, s) {
      // 兜底：即使刷新流程抛异常，页面也必须有可用状态（空列表 + 加载完成）
      print('[ScreenTime] onReady error: $e\n$s');
      state.loading = false;
      state.records = [];
      state.sessions = [];
      update();
    }
  }

  /// 刷新：先读本地数据立即展示，再把采集/网络同步放到后台（带超时），
  /// 保证页面不会被 WebDAV 连接卡住。
  ///
  /// 注意：方法名必须避开 refreshed 基类的 `refresh()`（ListNotifier 内置的
  /// 通知方法）。若覆盖 `refresh()`，`update()` 内部调用 `refresh()` 时会动态
  /// 分派到本方法 → 又 `update()` → 又 `refresh()`，形成无限同步递归导致
  /// 主线程 100% CPU 忙转（这正是「进入使用时间后无响应/ANR」的根因）。
  /// 因此这里命名为 `reload()`。
  Future<void> reload() async {
    print('[ST] refresh START');
    final sw = Stopwatch()..start();
    state.loading = true;
    state.lastError = null;
    update();
    state.recentDays = _buildRecentDays();
    await _loadDay();
    state.loading = false;
    state.loadedAt = DateTime.now();
    update();
    print('[ST] refresh loadDay done records=${state.records.length} ${sw.elapsedMilliseconds}ms');
    unawaited(_syncInBackground());
    print('[ST] refresh END');
  }

  Future<void> _syncInBackground() async {
    print('[ST] _syncInBackground START');
    try {
      final service = ScreenTimeService();
      state.granted = await service.isGranted();
      print('[ST] granted=${state.granted} hasOption=${WebDavUtil().hasOption}');
      if (state.granted) {
        // Android 已授权：采集 + 同步
        print('[ST] calling service.refresh()');
        await service.refresh();
        print('[ST] service.refresh() done');
      } else if (WebDavUtil().hasOption) {
        // 未授权（Android）或电脑端：仍拉取已同步的手机数据
        print('[ST] calling syncUsageRecords (20s timeout)');
        await WebDavUtil()
            .syncUsageRecords()
            .timeout(const Duration(seconds: 20), onTimeout: () {
          print('[ST] syncUsageRecords TIMEOUT');
        });
        print('[ST] syncUsageRecords done');
      }
      // 同步完成后刷新一次本地数据
      await _loadDay();
      update();
      print('[ST] _syncInBackground END');
    } catch (e) {
      // 网络/采集失败不打扰用户
      print('[ST] _syncInBackground error: $e');
    }
  }

  Future<void> selectDate(DateTime d) async {
    state.selectedDate = DateTime(d.year, d.month, d.day);
    update();
    await _loadDay();
    update();
  }

  /// 打开系统"使用情况访问"设置页（仅 Android）。
  Future<void> openSettings() async {
    await ScreenTimeService().openSettings();
    // 返回后自动刷新
    await Future<void>.delayed(const Duration(seconds: 1));
    await reload();
  }

  Future<void> _loadDay() async {
    try {
      state.records = await IsarUtil.getUsageByDay(dayKey(state.selectedDate));
    } catch (e, s) {
      // 本地查询异常：置空并记录，绝不让页面停留在"加载中"或白屏
      state.records = [];
      state.lastError = '$e';
      print('[ScreenTime] loadDay error: $e\n$s');
    }
    try {
      state.sessions =
          await IsarUtil.getUsageSessionsByDay(dayKey(state.selectedDate));
    } catch (e, s) {
      state.sessions = [];
      state.lastError = '$e';
      print('[ScreenTime] loadSessions error: $e\n$s');
    }
  }

  /// 切换视图（总览 / 时间线）
  void selectView(UsageViewMode mode) {
    state.viewMode = mode;
    update();
  }

  /// 切换"持续监督"开关：开启时请求通知权限（Android 13+ 显示常驻通知），
  /// 并让服务启动原生前台服务 + 分钟级轮询。
  Future<void> toggleMonitoring() async {
    if (state.monitorBusy) return;
    final enable = !state.monitoringEnabled;
    state.monitorBusy = true;
    update();
    try {
      if (enable && Platform.isAndroid) {
        // 未授予也只是隐藏通知，前台服务仍可运行，故不强制
        await Permission.notification.request();
      }
      await ScreenTimeService().setMonitoringEnabled(enable);
      state.monitoringEnabled = enable;
    } catch (e) {
      print('[ScreenTime] toggleMonitoring error: $e');
    } finally {
      state.monitorBusy = false;
      update();
    }
    // 开关变化后刷新一次本地时间线
    await _loadDay();
    update();
  }

  List<DateTime> _buildRecentDays() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    });
  }
}
