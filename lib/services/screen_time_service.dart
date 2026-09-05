import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moodiary/common/models/isar/usage_session.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/utils/session_builder.dart';
import 'package:moodiary/utils/usage_aggregator.dart';
import 'package:moodiary/utils/webdav_util.dart';

/// 屏幕使用时间采集服务（跨端单例）。
///
/// - Android：通过 UsageStatsManager（MethodChannel `moodiary/usage`）周期性
///   采集其他应用前台时长（`UsageRecord`）与前台会话（`UsageSession`），
///   并经 WebDAV 同步到电脑端。
/// - Windows/macOS/Linux：不采集，仅初始化时执行一次同步（拉取手机数据展示）。
///
/// 两种采集节奏：
/// - 常规：进前台 + 每 5 分钟（页面能快速看到数据）；
/// - 持续监督：开关打开后启动原生前台服务保持进程存活，主 isolate 每分钟
///   增量拉取事件流构建会话，实现分钟级精确监督。
class ScreenTimeService {
  static final ScreenTimeService _instance = ScreenTimeService._();
  factory ScreenTimeService() => _instance;
  ScreenTimeService._();

  static const MethodChannel _channel = MethodChannel('moodiary/usage');

  /// 持续监督轮询间隔
  static const Duration _monitorInterval = Duration(seconds: 60);

  Timer? _timer;
  Timer? _monitorTimer;
  AppLifecycleListener? _lifecycleListener;
  bool _collecting = false;
  bool _pollingSessions = false;
  bool _initialized = false;

  /// 应用名解析缓存（事件流本身不带应用名，按需拉取并缓存）
  final Map<String, String> _appLabelCache = {};

  /// 持续监督是否开启（持久化在本地配置，随启动恢复）
  bool get monitoringEnabled =>
      PrefUtil.getValue<bool>('usageMonitorEnabled') ?? false;

  /// 初始化：Android 启动采集 + 拉起进程保活前台服务。
  ///
  /// 前台服务（UsageMonitorService）**无条件**常驻：引擎保活后它让主 isolate
  /// 的定时器在 App 未打开/退后台时照常运行，实时监控与到点提醒不再依赖
  /// 「今天先进一次软件」。`monitoringEnabled` 开关只控制分钟级轮询节奏，
  /// 不再控制前台服务的起停（关掉开关 FGS 依然在，保进程）。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (Platform.isAndroid) {
      _startTimer();
      _initLifecycle();
      await _startForegroundService();
      if (monitoringEnabled) {
        _startPolling();
      }
    }
    // 不再在启动时立即拉/推一次：全新本地库时 `syncUsageRecords` 会在主
    // isolate 上串行拉取数百条记录，叠加日记同步会让启动期间主线程饱和
    // （表现为启动卡死/ANR）。数据新鲜度由"页面打开时 refresh"与 Android
    // 5 分钟定时采集兜底。
  }

  void dispose() {
    _timer?.cancel();
    _monitorTimer?.cancel();
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

  // ========== 持续监督开关 ==========

  /// 打开/关闭「分钟级轮询」：只控制轮询节奏并持久化开关。
  ///
  /// 前台服务（进程保活）由 [init] 无条件拉起后常驻，不再随开关起停；
  /// 关掉开关只是回到 5 分钟常规采集节奏，进程保活与提醒不受影响。
  Future<void> setMonitoringEnabled(bool enabled) async {
    await PrefUtil.setValue<bool>('usageMonitorEnabled', enabled);
    if (enabled) {
      _startPolling();
    } else {
      _stopPolling();
    }
    // 开关立即拉一次会话，让时间线马上更新
    await _pollSessions();
  }

  /// 拉起原生前台服务保活进程（只应由 [init] 调用；之后常驻，开关不关它）。
  Future<void> _startForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startMonitor');
    } catch (_) {
      // 启动失败（如系统限制）不阻断，靠常规采集兜底
    }
  }

  void _startPolling() {
    _monitorTimer?.cancel();
    _monitorTimer =
        Timer.periodic(_monitorInterval, (_) => unawaited(_pollSessions()));
  }

  void _stopPolling() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  // ========== 会话采集 ==========

  /// 增量拉取使用事件流，构建/更新前台会话（时间线、监督共同的数据地基）。
  ///
  /// 幂等：会话按 `start+包名` 确定性 id 覆盖，重复拉取不会产生重复数据；
  /// 游标推进到本次最大事件时刻，保证每条事件只被消费一次。
  Future<void> pollSessions() => _pollSessions();

  Future<void> _pollSessions() async {
    if (!Platform.isAndroid) return;
    if (!await isGranted()) return;
    if (_pollingSessions) return;
    _pollingSessions = true;
    try {
      final now = DateTime.now();
      // 首次拉取放宽到 6 小时：避免"打开应用前就已在前台的会话"因游标过近
      // 而丢失（其 RESUME 事件不在窗口内）。事件流保留数天，6 小时窗口安全。
      final cursor = PrefUtil.getValue<int>('usageSessionCursor') ??
          now
              .subtract(const Duration(hours: 6))
              .millisecondsSinceEpoch;
      final rawEvents = await _channel
              .invokeMethod<List<dynamic>>(
            'getEventsSince',
            {'since': cursor},
          )
              .timeout(const Duration(seconds: 15)) ??
          const [];
      if (rawEvents.isEmpty) return;

      final items =
          rawEvents.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final open = await IsarUtil.getMostRecentOpenUsageSession();
      final result = buildSessionsFromEvents(items, now: now, initialOpen: open);
      final sessions = [
        ...result.closed,
        if (result.open != null) result.open!,
      ];
      await _resolveLabels(sessions);
      await IsarUtil.putUsageSessions(sessions);

      // 推进游标到"最大事件时刻 + 1"，避免与 queryEvents 的含起点语义重复消费
      var maxT = cursor;
      for (final item in items) {
        final t = item['t'];
        if (t is num && t.toInt() > maxT) maxT = t.toInt();
      }
      await PrefUtil.setValue<int>('usageSessionCursor', maxT + 1);
    } catch (e) {
      // 拉取/落库失败不打扰用户，下次轮询再试
    } finally {
      _pollingSessions = false;
    }
  }

  /// 给缺失应用名的会话补全应用名（事件流不带名字，按包名拉取并缓存）。
  Future<void> _resolveLabels(List<UsageSession> sessions) async {
    for (final s in sessions) {
      if (s.appName.isNotEmpty) continue;
      final cached = _appLabelCache[s.packageName];
      if (cached != null) {
        s.appName = cached;
        continue;
      }
      try {
        final label = await _channel
            .invokeMethod<String>('getAppLabel', {'packageName': s.packageName});
        final resolved = (label == null || label.isEmpty) ? s.packageName : label;
        _appLabelCache[s.packageName] = resolved;
        s.appName = resolved;
      } catch (_) {
        s.appName = s.packageName;
      }
    }
  }

  /// 采集最近 [days] 天（含今天）并写入 Isar，然后同步。
  Future<void> _collect({int days = 7}) async {
    if (!Platform.isAndroid || _collecting) return;
    if (!await isGranted()) return;
    _collecting = true;
    try {
      final rawList = await _channel
              .invokeMethod<List<dynamic>>(
            'getUsage',
            {'days': days},
          )
              // 原生侧兜底超时：即使原生卡住，Dart 侧也不会无限等待
              .timeout(const Duration(seconds: 15)) ??
          const [];
      final items = rawList
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final grouped = groupUsageByDay(items);
      for (final entry in grouped.entries) {
        await IsarUtil.deleteUsageByDay(entry.key);
        await IsarUtil.putUsageRecords(entry.value);
      }
      // 清理 90 天前的过期数据（总时长 + 会话一起）
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      await IsarUtil.deleteUsageBefore(cutoff);
      await IsarUtil.deleteUsageSessionsBefore(cutoff);
      // 时间线/监督会话：同一次采集顺带增量更新
      await _pollSessions();
      await _sync();
    } catch (e) {
      // 采集失败不打扰用户，下次触发再试
    } finally {
      _collecting = false;
    }
  }

  /// 有 WebDAV 配置时同步使用时间记录 + 智能体元数据。
  /// 带整体超时，防止服务器慢时把 `_syncingUsage` 锁死导致后续同步全部跳过。
  Future<void> _sync() async {
    try {
      if (WebDavUtil().hasOption) {
        await WebDavUtil()
            .syncUsageRecords()
            .timeout(const Duration(seconds: 20), onTimeout: () {});
        // 画像 / 任务 / 聊天记录随 5 分钟采集节奏同步，分钟级到达另一端。
        await WebDavUtil()
            .syncMetadata()
            .timeout(const Duration(seconds: 20), onTimeout: () {});
      }
    } catch (_) {}
  }

  /// 公开入口：手动触发一次采集 + 同步（页面刷新时调用）。
  Future<void> refresh() async {
    await _collect();
  }
}
