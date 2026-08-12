import 'package:flutter/material.dart';

class WebDavOptions {
  static const String basePath = '/Moodiary';
  static const String imagePath = '/Moodiary/Asset/Image';
  static const String audioPath = '/Moodiary/Asset/Audio';
  static const String videoPath = '/Moodiary/Asset/Video';

  static const String diaryPath = '/Moodiary/Diary';
  static const String categoryPath = '/Moodiary/Category';

  //屏幕使用时间记录目录（v1 明文 JSON，独立于日记增量同步）
  static const String usagePath = '/Moodiary/Usage';

  //增量同步标记文件路径
  static const String syncFlagPath = '/Moodiary/sync.json';

  //使用时间记录的增量同步标记文件路径
  static const String usageSyncFlagPath = '/Moodiary/Usage/sync.json';

  // 连通性颜色标记
  static const Color connectivityColor = Color(0xFF4CAF50);
  static const Color unConnectivityColor = Color(0xFFF44336);
  static const Color connectingColor = Color(0xFFFFC107);
}

enum WebDavConnectivityStatus {
  connected,
  unconnected,
  connecting,
}
