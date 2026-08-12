import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/utils/usage_aggregator.dart';
import 'package:moodiary/utils/webdav_util.dart';

/// 屏幕使用时间采集服务（跨端单例）。
///
/// - Android：通过 UsageStatsManager（MethodChannel `moodiary/usage`）周期性
///   采集其他应用前台时长，写入 Isar `UsageRecord`，并经 WebDAV 同步到电脑端。
/// - Windows/macOS/Linux：不采集，仅初始化时执行一次同步（拉取手机数据展示）。
class ScreenTimeService {
  static final ScreenTimeService _instance = ScreenTimeService._();
  factory ScreenTimeService() => _instance;
  ScreenTimeService._();

  static const MethodChannel _channel = MethodChannel('moodiary/usage');

  Timer? _timer;
  AppLifecycleListener? _lifecycleListener;
  bool _collecting = false;
  bool _initialized = false;

  /// 初始化：Android 启动采集；两端都执行一次同步。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (Platform.isAndroid) {
      _startTimer();
      _initLifecycle();
    }
    // 两端都拉/推一次（PC 拉手机数据，手机传自己数据）
    unawaited(_sync());
  }

  void dispose() {
    _timer?.cancel();
    _lifecycleListener?.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _collect());
  }

  void _initLifecycle() {
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          unawaited(_collect());
        }
      },
    );
  }

  /// 是否已授予"使用情况访问"权限（仅 Android 有意义）。
  Future<bool> isGranted() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统"使用情况访问"设置页。
  Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  /// 采集最近 [days] 天（含今天）并写入 Isar，然后同步。
  Future<void> _collect({int days = 7}) async {
    if (!Platform.isAndroid || _collecting) return;
    if (!await isGranted()) return;
    _collecting = true;
    try {
      final rawList = await _channel.invokeMethod<List<dynamic>>(
            'getUsage',
            {'days': days},
          ) ??
          const [];
      final items = rawList
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final grouped = groupUsageByDay(items);
      for (final entry in grouped.entries) {
        await IsarUtil.deleteUsageByDay(entry.key);
        await IsarUtil.putUsageRecords(entry.value);
      }
      // 清理 90 天前的过期数据
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      await IsarUtil.deleteUsageBefore(cutoff);
      await _sync();
    } catch (e) {
      // 采集失败不打扰用户，下次触发再试
    } finally {
      _collecting = false;
    }
  }

  /// 有 WebDAV 配置时同步使用时间记录。
  Future<void> _sync() async {
    try {
      if (WebDavUtil().hasOption) {
        await WebDavUtil().syncUsageRecords();
      }
    } catch (_) {}
  }

  /// 公开入口：手动触发一次采集 + 同步（页面刷新时调用）。
  Future<void> refresh() async {
    await _collect();
  }
}
