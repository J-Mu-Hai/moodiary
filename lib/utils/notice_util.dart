import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:moodiary/services/app_ui_state.dart';
import 'package:refreshed/refreshed.dart';

class NoticeUtil {
  /// 惰性初始化：不再在类加载时 `FToast()..init(Get.overlayContext!)`——
  /// 引擎保活后 App 可能长时间无界面（detached），`Get.overlayContext!`
  /// 直接崩；只有界面可用（resumed）时才需要建 toast 上下文。
  static FToast? _fToast;

  static FToast get _toast {
    final t = _fToast ?? (FToast()..init(Get.overlayContext!));
    _fToast ??= t;
    return t;
  }

  static void showToast(String message) {
    // 界面不可用时丢弃 App 内 toast：后台提醒走系统通知
    // （AgentChannel.showAgentNotification），不依赖 overlay。
    if (!AppUiState.instance.uiAvailable) return;
    final fToast = _toast;
    late final colorScheme = Theme.of(Get.context!).colorScheme;
    fToast.removeCustomToast();
    fToast.showToast(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          color: colorScheme.primaryContainer.withValues(alpha: 0.8),
        ),
        child: Text(
          message,
          style:
              TextStyle(fontSize: 16.0, color: colorScheme.onPrimaryContainer),
        ),
      ),
      gravity: ToastGravity.CENTER,
    );
  }

  static void showLoading({String message = '加载中'}) {
    if (!AppUiState.instance.uiAvailable) return;
    final fToast = _toast;
    fToast.removeCustomToast();
    fToast.showToast(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          color: Colors.black.withAlpha(200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(width: 16.0),
            Text(
              message,
              style: const TextStyle(fontSize: 16.0, color: Colors.white),
            ),
          ],
        ),
      ),
      gravity: ToastGravity.CENTER,
      toastDuration: const Duration(seconds: 10),
    );
  }

  static void showBug({required String message}) {
    if (kDebugMode) return;
    if (!AppUiState.instance.uiAvailable) return;
    final fToast = _toast;
    fToast.removeCustomToast();
    fToast.showToast(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          color: Colors.redAccent.withAlpha((240)),
        ),
        child: Text(
          message,
          style: const TextStyle(fontSize: 16.0, color: Colors.white),
        ),
      ),
      gravity: ToastGravity.CENTER,
      toastDuration: const Duration(seconds: 2),
    );
  }
}
