import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:moodiary/utils/file_util.dart';
import 'package:moodiary/utils/notice_util.dart';

class LogUtil {
  static final Logger _logger = Logger(
    output: kDebugMode
        ? ConsoleOutput()
        : FileOutput(file: File(FileUtil.getErrorLogPath())),
    filter: kDebugMode ? DevelopmentFilter() : ProductionFilter(),
  );

  static void printError(message,
      {required Object error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    NoticeUtil.showBug(message: '$message\n${error.toString()}');
  }

  static void printWTF(message,
      {required Object error, StackTrace? stackTrace}) {
    _logger.f(message, error: error, stackTrace: stackTrace);
    NoticeUtil.showBug(message: '$message\n${error.toString()}');
  }

  static void printInfo(message) {
    if (kDebugMode) _logger.i(message);
  }

  /// 写一条警告级诊断日志：debug → 控制台，release → error.log，不弹 bug 窗。
  /// warning 级别两种 filter 都放行，适合记录「AI 请求失败的确切 URL/状态码」
  /// 这类需要事后定位、但不应打扰用户的诊断信息。
  static void logToFile(String message) {
    _logger.w(message);
  }
}
