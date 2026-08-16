import 'dart:io';

import 'package:flutter/services.dart';

/// 智能体原生通道 — 与 Android MainActivity 的 `moodiary/agent` MethodChannel 通信。
///
/// 提供两个工具能力（配合 agent_executor 的 open_diary / block_screen 使用）：
/// - [bringToFront]：让 moodiary 自己回到前台（用户澄清「弹出软件」= 弹出
///   moodiary 本身，而非拉起外部 App）。Android 12+ 后台受限时仅在 App 存活
///   （前台或 UsageMonitorService 保活期间）有效。
/// - [setKeepScreenOn]：设置/复位屏幕常亮（强制锁屏期间保持亮屏）。
///
/// 非 Android 平台直接 no-op，避免桌面端崩溃。
class AgentChannel {
  static const MethodChannel _channel = MethodChannel('moodiary/agent');

  /// 把 moodiary 带回前台。
  static Future<void> bringToFront() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('bringToFront');
    } catch (e) {
      print('[AgentChannel] bringToFront 失败: $e');
    }
  }

  /// 设置/复位屏幕常亮。
  static Future<void> setKeepScreenOn(bool keep) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setKeepScreenOn', {'keep': keep});
    } catch (e) {
      print('[AgentChannel] setKeepScreenOn 失败: $e');
    }
  }

  /// 是否已授予系统「悬浮窗」权限（显示在其他应用上层）。
  static Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } catch (e) {
      print('[AgentChannel] hasOverlayPermission 失败: $e');
      return false;
    }
  }

  /// 未授权时跳转系统「悬浮窗权限」设置页（一次授权后长期可用）。
  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      print('[AgentChannel] requestOverlayPermission 失败: $e');
    }
  }

  /// 显示系统级强制锁屏悬浮窗（全屏覆盖所有应用，拦截 Home 手势）。
  static Future<void> showForceLock({
    required String title,
    required String reason,
    required int durationMinutes,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('showForceLock', {
        'title': title,
        'reason': reason,
        'durationMinutes': durationMinutes,
      });
    } catch (e) {
      print('[AgentChannel] showForceLock 失败: $e');
    }
  }

  /// 刷新悬浮窗倒计时文本（锁屏期间每秒调用）。
  static Future<void> updateForceLock(int secondsLeft) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('updateForceLock', {'secondsLeft': secondsLeft});
    } catch (e) {
      print('[AgentChannel] updateForceLock 失败: $e');
    }
  }

  /// 移除强制锁屏悬浮窗（幂等）。
  static Future<void> hideForceLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('hideForceLock');
    } catch (e) {
      print('[AgentChannel] hideForceLock 失败: $e');
    }
  }

  /// 是否正通过蓝牙耳机（A2DP/SCO）输出音频。
  ///
  /// 用于「发起会话」决策：耳机在 → 先语音播报开场白；无耳机 → 直接切对话页
  /// （避免公开场合外放）。Android 原生用免权限的 AudioManager 查询实现。
  static Future<bool> isBluetoothHeadset() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasBluetoothHeadset') ?? false;
    } catch (e) {
      print('[AgentChannel] hasBluetoothHeadset 失败: $e');
      return false;
    }
  }
}
