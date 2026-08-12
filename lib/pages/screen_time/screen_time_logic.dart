import 'dart:async';

import 'package:flutter/services.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/services/screen_time_service.dart';
import 'package:moodiary/utils/webdav_util.dart';
import 'package:refreshed/refreshed.dart';

import 'screen_time_state.dart';

class ScreenTimeLogic extends GetxController {
  final ScreenTimeState state = ScreenTimeState();

  /// 与 Isar 的 yMd 索引一致的日期键，形如 `2026/8/8`
  static String dayKey(DateTime d) => '${d.year}/${d.month}/${d.day}';

  @override
  void onReady() async {
    super.onReady();
    await refresh();
  }

  /// 刷新：先读本地数据立即展示，再把采集/网络同步放到后台（带超时），
  /// 保证页面不会被 WebDAV 连接卡住。
  Future<void> refresh() async {
    state.loading = true;
    update();
    state.recentDays = _buildRecentDays();
    await _loadDay();
    state.loading = false;
    update();
    unawaited(_syncInBackground());
  }

  Future<void> _syncInBackground() async {
    try {
      final service = ScreenTimeService();
      state.granted = await service.isGranted();
      if (state.granted) {
        // Android 已授权：采集 + 同步
        await service.refresh();
      } else if (WebDavUtil().hasOption) {
        // 未授权（Android）或电脑端：仍拉取已同步的手机数据
        await WebDavUtil()
            .syncUsageRecords()
            .timeout(const Duration(seconds: 20), onTimeout: () {});
      }
      // 同步完成后刷新一次本地数据
      await _loadDay();
      update();
    } catch (_) {
      // 网络/采集失败不打扰用户
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
    await refresh();
  }

  Future<void> _loadDay() async {
    state.records = await IsarUtil.getUsageByDay(dayKey(state.selectedDate));
  }

  List<DateTime> _buildRecentDays() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    });
  }
}
