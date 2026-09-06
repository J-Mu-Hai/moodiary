import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:moodiary/pages/home/diary/diary_logic.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/app_ui_state.dart';
import 'package:moodiary/utils/webdav_util.dart';
import 'package:refreshed/refreshed.dart';

/// 跨端「打开即在同步」的轻量守护（单 isolate，全部在 Dart 主 isolate 的
/// Timer 上，不引入后台 isolate）。
///
/// 解决的问题：画像/任务/聊天/使用时间等数据的拉取大多只在**具体页面打开时**
/// 触发（助手页 10s 轮询、使用时间页/分析页打开即拉、日记首页 onInit 一次）。
/// 两端各自打开后若停留在别的页面，另一端产生的数据不会自动到达——这正是
/// 「打开手机版/电脑版却要等很久才看到同步」的根因之一。另外 Android 引擎
/// 保活后 Activity 重建不会重跑 onInit，单纯依赖页面初始化拉取会有空窗。
///
/// 节奏（每次调用都带防重入锁与「内容指纹免下载」逻辑，量小不拖主线程）：
/// - 回到前台 / 启动后 ~3s：立即轻量拉一次元数据（画像/任务/聊天…），
///   若开启 autoSync 顺带拉一次日记增量（引擎保活后的「再次打开」也覆盖）；
/// - 每 60s：`syncMetadata(pullOnly)`（Android 仅前台时跑，省电）；
/// - 每 5min：完整双向元数据；Windows 额外拉取手机采集的使用时间记录
///   （Android 的采集/上传由 ScreenTimeService 每 5 分钟负责）；
/// - 每 5min：`autoSync` 开启时拉一次日记增量（界面附着时才刷新列表）。
class SyncKeeperService {
  SyncKeeperService._();

  static final SyncKeeperService _instance = SyncKeeperService._();
  factory SyncKeeperService() => _instance;

  Timer? _metaTimer;
  Timer? _fullTimer;
  Timer? _diaryTimer;
  AppLifecycleListener? _lifecycle;
  bool _started = false;

  bool get _hasOption => WebDavUtil().hasOption;

  /// 启动守护（幂等）。WebDAV 配置「从无到有」时（设置页保存成功）可再次
  /// 调用以补启；删除配置用 [stop]。
  void start() {
    if (_started) return;
    _started = true;
    if (!_hasOption) return; // 尚未配置 WebDAV：等 start() 被再次调用

    // 回到前台 = 用户「打开本端」：立即对齐一次，不等下一个周期
    // （覆盖引擎保活后 Activity 重建不重跑页面 onInit 的空窗）。
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.resumed) {
        unawaited(_syncMetaPull());
        if (PrefUtil.getValue<bool>('autoSync') == true) {
          unawaited(_syncDiaries());
        }
      }
    });

    // 启动后先对齐一次轻量元数据，不阻塞首帧（post-frame + 延迟）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 3), _syncMetaPull);
    });

    _metaTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _syncMetaPull());
    _fullTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _syncFull());
    _diaryTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _syncDiaries());
    print('[SyncKeeper] 跨端轻量同步已启动：60s 元数据 / 5min 全量+日记');
  }

  /// 停止守护（删除 WebDAV 配置时调用）。
  void stop() {
    _metaTimer?.cancel();
    _metaTimer = null;
    _fullTimer?.cancel();
    _fullTimer = null;
    _diaryTimer?.cancel();
    _diaryTimer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _started = false;
  }

  Future<void> _syncMetaPull() async {
    if (!_hasOption) return;
    // Android 非前台（退后台/熄屏）跳过 60s 轻拉省电：
    // 5min 全量同步与 ScreenTimeService 仍会兜底；桌面无此顾虑。
    if (Platform.isAndroid && !AppUiState.instance.uiAvailable) return;
    try {
      await WebDavUtil().syncMetadata(pullOnly: true);
    } catch (e) {
      print('[SyncKeeper] meta pull 失败: $e');
    }
  }

  Future<void> _syncFull() async {
    if (!_hasOption) return;
    try {
      // 双向元数据：本地改动推上去、远端改动拉下来（一次 1~3 个小请求）。
      await WebDavUtil().syncMetadata();
      // Windows 没有采集器：把手机采集的使用时间记录拉下来；Android 的
      // usage 采集/上传由 ScreenTimeService 每 5 分钟负责，这里不重复。
      if (!Platform.isAndroid) {
        await WebDavUtil().syncUsageRecords();
      }
    } catch (e) {
      print('[SyncKeeper] full sync 失败: $e');
    }
  }

  Future<void> _syncDiaries() async {
    if (!_hasOption) return;
    if (PrefUtil.getValue<bool>('autoSync') != true) return;
    if (!AppUiState.instance.uiAttached) return;
    try {
      final diary = await IsarUtil.getAllDiaries();
      var downloaded = 0;
      await WebDavUtil().syncDiary(diary, onDownload: () {
        downloaded++;
      });
      // 下载到新内容且界面在 → 整体刷新一次日记列表。
      if (downloaded > 0 && Get.isRegistered<DiaryLogic>()) {
        await Get.find<DiaryLogic>().refreshAll();
      }
    } catch (e) {
      print('[SyncKeeper] diary sync 失败: $e');
    }
  }
}
