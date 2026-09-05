import 'package:flutter/widgets.dart';

/// 全局 UI 可用性信号 — 引擎保活后区分「引擎在跑」与「界面在显示」。
///
/// 后台守护模式下 Flutter 引擎在 Activity 销毁后仍存活（Dart 定时器照常跑），
/// 但**界面**可能已经不存在（`detached`）或退到后台（`paused`/`hidden`）。
/// 需要界面的能力（Get 导航、FToast、bringToFront、悬浮窗锁屏）只能在
/// `lifecycleState == resumed` 时调用；否则应降级为系统通知（[AgentChannel.showAgentNotification]）。
///
/// 直接用 `WidgetsBinding.instance.lifecycleState` 实时读取，框架在 Activity
/// 销毁/重建时会把它切到 detached/resumed，无需维护独立状态。
class AppUiState {
  AppUiState._();
  static final AppUiState instance = AppUiState._();

  /// 界面完全可用（可导航、可弹 toast、可开悬浮窗）。
  bool get uiAvailable =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// 引擎是否仍附着着界面（非 detached；后台/前台都算附着）。
  bool get uiAttached =>
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached;
}
