import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' as flutter;
import 'package:moodiary/common/models/isar/category.dart';
import 'package:moodiary/common/models/isar/diary.dart';
import 'package:moodiary/common/models/isar/usage_record.dart';
import 'package:moodiary/common/values/webdav.dart';
import 'package:moodiary/pages/home/diary/diary_logic.dart';
import 'package:moodiary/presentation/isar.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/presentation/secure_storage.dart';
import 'package:moodiary/utils/aes_util.dart';
import 'package:moodiary/utils/file_util.dart';
import 'package:moodiary/utils/log_util.dart';
import 'package:refreshed/refreshed.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

class WebDavUtil {
  RxSet<String> syncingDiaries = <String>{}.obs;

  /// 使用时间记录同步的防重入锁
  bool _syncingUsage = false;

  webdav.Client? _client;

  List<String> get options => PrefUtil.getValue<List<String>>('webDavOption')!;

  bool get hasOption =>
      PrefUtil.getValue<List<String>>('webDavOption')!.isNotEmpty;

  WebDavUtil._();

  static final WebDavUtil _instance = WebDavUtil._();

  factory WebDavUtil() => _instance;

  Future<void> initWebDav() async {
    final webDavOption = options;
    if (webDavOption.isEmpty) {
      _client = null;
      return;
    }
    if (_client != null) {
      _client = null;
    }
    // 尝试连接，如果失败，
    try {
      _client = webdav.newClient(
        webDavOption[0],
        user: webDavOption[1],
        password: webDavOption[2],
        debug: false,
      );
    } catch (e) {
      _client = null;
      return;
    }
    _client?.setHeaders({
      'accept-charset': 'utf-8',
      'Content-Type': 'application/json',
    });
    // 连接超时 10s，防止服务器不可达时请求无限期挂起
    _client?.setConnectTimeout(10000);
  }

  Future<bool> checkConnectivity() async {
    if (_client == null) {
      return false;
    }
    try {
      // 设置超时时间为 5 秒
      await _client?.ping().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Ping operation timed out');
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> initDir() async {
    await _client!.mkdirAll(WebDavOptions.imagePath);
    await _client!.mkdirAll(WebDavOptions.videoPath);
    await _client!.mkdirAll(WebDavOptions.audioPath);
    await _client!.mkdirAll(WebDavOptions.diaryPath);
    await _client!.mkdirAll(WebDavOptions.categoryPath);
    await _client!.mkdirAll(WebDavOptions.usagePath);
    await checkSyncFlag();
  }

  Future<void> checkSyncFlag() async {
    try {
      await _client!.read(WebDavOptions.syncFlagPath);
    } catch (e) {
      await _client!
          .write(WebDavOptions.syncFlagPath, utf8.encode(jsonEncode({})));
    }
  }

  Future<void> updateWebDav(
      {required String baseUrl,
      required String username,
      required String password}) async {
    await PrefUtil.setValue('webDavOption', [baseUrl, username, password]);
    await initWebDav();
  }

  Future<void> removeWebDavOption() async {
    _client = null;
    await PrefUtil.setValue<List<String>>('webDavOption', []);
  }

  Future<Map<String, String>> fetchServerSyncData() async {
    if (_client != null) {
      final response = await _client!.read(WebDavOptions.syncFlagPath);
      if (response.isNotEmpty) {
        return Map<String, String>.from(jsonDecode(utf8.decode(response)));
      }
    }
    return {};
  }

  Future<void> updateServerSyncData(Map<String, String> syncData) async {
    if (_client != null) {
      await _client!
          .write(WebDavOptions.syncFlagPath, utf8.encode(jsonEncode(syncData)));
    }
  }

  //删除某一篇日记，将webdav中sync.json的对应日记id的value设置为delete
  Future<void> deleteSingleDiary(Diary diary) async {
    final serverSyncData = await fetchServerSyncData();
    if (!serverSyncData.containsKey(diary.id)) {
      return;
    }
    serverSyncData[diary.id] = 'delete';
    await updateServerSyncData(serverSyncData);
    // 删除日记json
    await _client!.remove('${WebDavOptions.diaryPath}/${diary.id}.json');
    await _client!.remove('${WebDavOptions.diaryPath}/${diary.id}.bin');
    // 遍历删除日记资源文件
    await _deleteFiles(
        diary.imageName, '${WebDavOptions.imagePath}/${diary.id}', 'image');
    await _deleteFiles(
        diary.audioName, '${WebDavOptions.audioPath}/${diary.id}', 'audio');
    await _deleteFiles(
        diary.videoName, '${WebDavOptions.videoPath}/${diary.id}', 'video');
    await _deleteFiles(
        diary.videoName
            .map((videoName) => 'thumbnail-${videoName.substring(6, 42)}.jpeg')
            .toList(),
        '${WebDavOptions.videoPath}/${diary.id}',
        'thumbnail');
    // 删除对应目录
    await _client!.remove('${WebDavOptions.imagePath}/${diary.id}');
    await _client!.remove('${WebDavOptions.audioPath}/${diary.id}');
    await _client!.remove('${WebDavOptions.videoPath}/${diary.id}');
  }

  Future<void> _deleteDiary(Diary diary) async {
    // 删除文件的通用方法
    Future<void> deleteFiles(List<String> names, String folder) async {
      final tasks = names
          .map(
              (name) => FileUtil.deleteFile(FileUtil.getRealPath(folder, name)))
          .toList();
      await Future.wait(tasks);
    }

    // 删除日记和关联文件
    if (await IsarUtil.deleteADiary(diary.isarId)) {
      // 并行删除图片、音频、视频及其缩略图
      await Future.wait([
        deleteFiles(diary.imageName, 'image'),
        deleteFiles(diary.audioName, 'audio'),
        deleteFiles(diary.videoName, 'video'),
        deleteFiles(diary.videoName, 'thumbnail'), // 视频缩略图
      ]);
    }
  }

  Future<void> syncDiary(
    List<Diary> localDiaries, {
    flutter.VoidCallback? onUpload,
    flutter.VoidCallback? onDownload,
    flutter.VoidCallback? onComplete,
  }) async {
    final serverSyncData = await fetchServerSyncData();
    final Map<String, String> updatedSyncData = {...serverSyncData};

    // 本地日记的 ID -> 修改时间映射
    final Map<String, String> localDiaryMap = {
      for (final diary in localDiaries)
        diary.id: diary.lastModified.toIso8601String()
    };

    for (final entry in serverSyncData.entries) {
      final diaryId = entry.key;
      final serverLastModified = entry.value;

      if (syncingDiaries.contains(diaryId)) {
        continue; // 正在同步中，跳过
      }

      final localLastModified = localDiaryMap[diaryId];
      //如果本地还有日记，但服务器中的日记已经被删除
      if (serverLastModified == 'delete') {
        if (localLastModified != null) {
          syncingDiaries.add(diaryId);
          try {
            await _deleteDiary(
                localDiaries.firstWhere((element) => element.id == diaryId));
            Bind.find<DiaryLogic>().refreshAll();
          } finally {
            // 无论成功与否都必须清除，否则 Rive 同步按钮会永转
            syncingDiaries.remove(diaryId);
          }
        }
        continue;
      }

      //本地不存在该日记，下载
      if (localLastModified == null) {
        syncingDiaries.add(diaryId);
        try {
          final updatedDiary = await _downloadDiary(diaryId); // 下载日记的实现
          await IsarUtil.insertADiary(updatedDiary); // 保存到本地的实现
        } catch (e) {
          updatedSyncData.remove(diaryId);
        }
        onDownload?.call();

        syncingDiaries.remove(diaryId);
      }
      // 本地存在该日记，但服务器版本较新，更新本地
      if (localLastModified != null &&
          serverLastModified.compareTo(localLastModified) > 0) {
        syncingDiaries.add(diaryId);
        final oldDiary =
            localDiaries.firstWhere((element) => element.id == diaryId);
        try {
          final newDiary = await _downloadDiary(diaryId);
          await IsarUtil.updateADiary(oldDiary: oldDiary, newDiary: newDiary);
        } catch (e) {
          // 下载失败，移除sync.json中的记录
          updatedSyncData.remove(diaryId);
        }
        onDownload?.call();
        syncingDiaries.remove(diaryId);
      }
    }

    for (final diary in localDiaries) {
      if (syncingDiaries.contains(diary.id)) {
        continue; // 正在同步中，跳过
      }

      final serverLastModified = serverSyncData[diary.id];
      final localLastModified = diary.lastModified.toIso8601String();

      if (serverLastModified == null ||
          serverLastModified.compareTo(localLastModified) < 0) {
        // 服务器不存在该日记，或服务器版本较旧
        syncingDiaries.add(diary.id);
        try {
          await _uploadDiary(diary); // 上传日记的实现
          onUpload?.call();
          updatedSyncData[diary.id] = localLastModified;
        } finally {
          // 上传抛异常也必须清除，否则 Rive 同步按钮会永转
          syncingDiaries.remove(diary.id);
        }
      }
    }

    // 更新服务器的同步 JSON 文件
    await updateServerSyncData(updatedSyncData);
    onComplete?.call();
  }

  /// 读取使用时间记录的同步标记（recordId -> lastModified ISO）
  Future<Map<String, String>> fetchUsageSyncData() async {
    if (_client == null) return {};
    try {
      final response = await _client!
          .read(WebDavOptions.usageSyncFlagPath)
          .timeout(const Duration(seconds: 15));
      if (response.isNotEmpty) {
        return Map<String, String>.from(jsonDecode(utf8.decode(response)));
      }
    } catch (_) {
      // 标记文件尚未创建，视为空
    }
    return {};
  }

  /// 写回使用时间记录的同步标记
  Future<void> updateUsageSyncData(Map<String, String> syncData) async {
    if (_client == null) return;
    await _client!
        .write(WebDavOptions.usageSyncFlagPath, utf8.encode(jsonEncode(syncData)))
        .timeout(const Duration(seconds: 15));
  }

  /// 屏幕使用时间记录的双向增量同步。
  ///
  /// 与 [syncDiary] 同一套"同步标记 + 逐条 JSON"范式，但使用独立的
  /// `/Moodiary/Usage/sync.json` 与 `<id>.json`，不影响日记同步。
  /// 手机端采集后上传，电脑端下拉展示。
  Future<void> syncUsageRecords({
    flutter.VoidCallback? onUpload,
    flutter.VoidCallback? onDownload,
    flutter.VoidCallback? onComplete,
  }) async {
    if (_client == null || _syncingUsage) return;
    _syncingUsage = true;
    try {
      final serverSyncData = await fetchUsageSyncData();
      final updatedSyncData = {...serverSyncData};
      final localRecords = await IsarUtil.getAllUsageRecords();
      final localMap = {
        for (final r in localRecords) r.id: r.lastModified.toIso8601String()
      };
      print('[SYNC] usage: local=${localRecords.length} server=${serverSyncData.length}');

      // 服务器侧：处理删除标记 / 本地缺失或较旧的记录下载。
      // 限制单次下载量：历史版本用随机 id 累积了海量服务器文件，若一次性
      // 全量下载会长时间占满主 isolate（卡死）。逐次同步缓慢收敛。
      var downloaded = 0;
      const maxDownloadPerSync = 300;
      for (final entry in serverSyncData.entries) {
        final id = entry.key;
        final serverLastModified = entry.value;
        final localLastModified = localMap[id];
        if (serverLastModified == 'delete') {
          if (localLastModified != null) {
            await IsarUtil.deleteUsageRecord(id);
            onDownload?.call();
          }
          continue;
        }
        if (downloaded >= maxDownloadPerSync) {
          break;
        }
        if (localLastModified == null ||
            serverLastModified.compareTo(localLastModified) > 0) {
          try {
            final data = await _client!
                .read('${WebDavOptions.usagePath}/$id.json')
                .timeout(const Duration(seconds: 15));
            final record = UsageRecord.fromJson(
                jsonDecode(utf8.decode(data)) as Map<String, dynamic>);
            await IsarUtil.putUsageRecords([record]);
            downloaded++;
            onDownload?.call();
          } catch (e) {
            // 下载失败，移除标记避免反复尝试
            updatedSyncData.remove(id);
          }
        }
      }

      // 本地侧：服务器缺失或较旧的记录上传
      var uploaded = 0;
      for (final record in localRecords) {
        final serverLastModified = serverSyncData[record.id];
        final localLastModified = record.lastModified.toIso8601String();
        if (serverLastModified == null ||
            serverLastModified.compareTo(localLastModified) < 0) {
          try {
            _client!.setHeaders({
              'accept-charset': 'utf-8',
              'Content-Type': 'application/json',
            });
            await _client!
                .write(
                  '${WebDavOptions.usagePath}/${record.id}.json',
                  utf8.encode(jsonEncode(record.toJson())),
                )
                .timeout(const Duration(seconds: 15));
            onUpload?.call();
            uploaded++;
            updatedSyncData[record.id] = localLastModified;
          } catch (e) {
            LogUtil.printInfo('Failed to upload usage record: $e');
          }
        }
      }

      print('[SYNC] usage done: downloaded=$downloaded uploaded=$uploaded');
      await updateUsageSyncData(updatedSyncData);
      onComplete?.call();
    } finally {
      _syncingUsage = false;
    }
  }

  Future<void> uploadSingleDiary(
    Diary diary, {
    flutter.VoidCallback? onUpload,
    flutter.VoidCallback? onComplete,
  }) async {
    if (syncingDiaries.contains(diary.id)) {
      return; // 避免重复上传
    }

    syncingDiaries.add(diary.id);
    try {
      // 上传日记到服务器
      await _uploadDiary(diary); // 上传日记的实现

      // 更新服务器同步数据
      final serverSyncData = await fetchServerSyncData();
      serverSyncData[diary.id] = diary.lastModified.toIso8601String();
      await updateServerSyncData(serverSyncData);

      onUpload?.call();
    } catch (e) {
      LogUtil.printInfo('Failed to upload diary: $e');
    } finally {
      syncingDiaries.remove(diary.id);
      onComplete?.call(); // 调用完成回调
    }
  }

  Future<void> updateSingleDiary({
    required Diary oldDiary,
    required Diary newDiary,
    flutter.VoidCallback? onUpload,
    flutter.VoidCallback? onComplete,
  }) async {
    if (syncingDiaries.contains(newDiary.id)) {
      return; // 避免重复上传
    }
    syncingDiaries.add(newDiary.id);
    try {
      // 遍历删除日记资源文件
      final needToDeleteImage = oldDiary.imageName
          .where((element) => !newDiary.imageName.contains(element))
          .toList();
      final needToDeleteAudio = oldDiary.audioName
          .where((element) => !newDiary.audioName.contains(element))
          .toList();
      final needToDeleteVideo = oldDiary.videoName
          .where((element) => !newDiary.videoName.contains(element))
          .toList();
      final needToDeleteThumbnail = needToDeleteVideo
          .map((videoName) => 'thumbnail-${videoName.substring(6, 42)}.jpeg')
          .toList();
      await _deleteFiles(needToDeleteImage,
          '${WebDavOptions.imagePath}/${newDiary.id}', 'image');
      await _deleteFiles(needToDeleteAudio,
          '${WebDavOptions.audioPath}/${newDiary.id}', 'audio');
      await _deleteFiles(needToDeleteVideo,
          '${WebDavOptions.videoPath}/${newDiary.id}', 'video');
      await _deleteFiles(needToDeleteThumbnail,
          '${WebDavOptions.videoPath}/${newDiary.id}', 'thumbnail');
      // 上传日记到服务器
      await _uploadDiary(newDiary); // 上传日记的实现
      // 更新服务器同步数据
      final serverSyncData = await fetchServerSyncData();
      serverSyncData[newDiary.id] = newDiary.lastModified.toIso8601String();
      await updateServerSyncData(serverSyncData);
      onUpload?.call();
    } catch (e) {
      LogUtil.printInfo('Failed to upload diary: $e');
    } finally {
      syncingDiaries.remove(newDiary.id);
      onComplete?.call(); // 调用完成回调
    }
  }

  Future<bool> _checkShouldEncrypt() async {
    return PrefUtil.getValue<bool>('syncEncryption') == true &&
        (await SecureStorageUtil.getValue('userKey')) != null;
  }

  Future<void> _uploadDiary(Diary diary) async {
    Uint8List diaryData;
    String diaryPath;
    // 检查有没有开启加密
    final shouldEncrypt = await _checkShouldEncrypt();
    if (shouldEncrypt) {
      // 尝试获取用户密钥
      final userKey = await SecureStorageUtil.getValue('userKey');
      // 生成加密密钥, 用日记 ID 和用户密钥生成
      final key = await AesUtil.deriveKey(salt: diary.id, userKey: userKey!);
      // 加密日记内容
      diaryPath = '${WebDavOptions.diaryPath}/${diary.id}.bin';
      diaryData =
          await AesUtil.encrypt(key: key, data: jsonEncode(diary.toJson()));
    } else {
      diaryPath = '${WebDavOptions.diaryPath}/${diary.id}.json';
      diaryData = utf8.encode(jsonEncode(diary.toJson()));
    }

    // 检查并上传分类
    if (diary.categoryId != null) {
      final categoryName =
          IsarUtil.getCategoryName(diary.categoryId!)?.categoryName;
      if (categoryName != null) {
        await _uploadCategory(diary.categoryId!, categoryName);
      }
    }
    try {
      _client!.setHeaders({
        'accept-charset': 'utf-8',
        'Content-Type':
            shouldEncrypt ? 'application/octet-stream' : 'application/json',
      });
      await _client!.write(diaryPath, diaryData);
      LogUtil.printInfo('Diary  uploaded: $diaryPath');
    } catch (e) {
      LogUtil.printInfo('Failed to upload diary : $e');
      rethrow;
    }

    // 上传资源文件，目标路径是资源文件夹下的日记id
    await _uploadFiles(
        diary.imageName, '${WebDavOptions.imagePath}/${diary.id}', 'image');
    await _uploadFiles(
        diary.audioName, '${WebDavOptions.audioPath}/${diary.id}', 'audio');
    await _uploadFiles(
        diary.videoName, '${WebDavOptions.videoPath}/${diary.id}', 'video');
    await _uploadFiles(
        diary.videoName, '${WebDavOptions.videoPath}/${diary.id}', 'thumbnail');
  }

  Future<void> _uploadFiles(
      List<String> fileNames, String resourcePath, String type) async {
    await _client!.mkdirAll(resourcePath);
    final existingFiles = await _client!.readDir(resourcePath);

    for (var fileName in fileNames) {
      final filePath = FileUtil.getRealPath(type, fileName);
      fileName = type == 'thumbnail'
          ? 'thumbnail-${fileName.substring(6, 42)}.jpeg'
          : fileName;
      if (existingFiles.any((file) => file.name == fileName)) {
        LogUtil.printInfo('$type file already exists: $fileName');
        continue;
      }
      try {
        final fileBytes = await File(filePath).readAsBytes();
        _client!.setHeaders({
          'accept-charset': 'utf-8',
          'Content-Type': 'application/octet-stream',
        });
        await _client!.write('$resourcePath/$fileName', fileBytes);
        LogUtil.printInfo('$type file uploaded: $fileName');
      } catch (e) {
        LogUtil.printInfo('Failed to upload $type file: $fileName, Error: $e');
        rethrow;
      }
    }
  }

  Future<void> _deleteFiles(
      List<String> fileNames, String resourcePath, String type) async {
    for (final fileName in fileNames) {
      try {
        await _client!.remove('$resourcePath/$fileName');
        LogUtil.printInfo('$type file deleted: $fileName');
      } catch (e) {
        LogUtil.printInfo('Failed to delete $type file: $fileName, Error: $e');
        rethrow;
      }
    }
  }

  Future<Diary> _downloadDiary(String diaryId) async {
    // 下载日记 JSON 数据
    final normalDiaryPath = '${WebDavOptions.diaryPath}/$diaryId.json';
    final encryptedDiaryPath = '${WebDavOptions.diaryPath}/$diaryId.bin';
    late Diary diary;
    try {
      // 先尝试普通 JSON 格式
      try {
        final diaryData = await _client!.read(normalDiaryPath);
        diary = await flutter.compute(Diary.fromJson,
            jsonDecode(utf8.decode(diaryData)) as Map<String, dynamic>);
        LogUtil.printInfo('Diary JSON downloaded: $normalDiaryPath');
      } catch (e) {
        LogUtil.printInfo('Failed to download normal JSON: $e');
        // 再尝试二进制格式
        try {
          final encryptedDiaryData = await _client!.read(encryptedDiaryPath);
          // 解密日记内容
          final userKey = await SecureStorageUtil.getValue('userKey');
          final shouldEncrypt = await _checkShouldEncrypt();
          if (!shouldEncrypt) {
            throw Exception('User key not found or encryption not enabled');
          }
          final key = await AesUtil.deriveKey(salt: diaryId, userKey: userKey!);
          final decryptedData = await AesUtil.decrypt(
            key: key,
            encryptedData: Uint8List.fromList(encryptedDiaryData),
          );
          diary = await flutter.compute(Diary.fromJson,
              jsonDecode(decryptedData) as Map<String, dynamic>);
          LogUtil.printInfo('Diary binary downloaded: $encryptedDiaryPath');
        } catch (e) {
          LogUtil.printInfo('Failed to download binary diary: $e');
          // 两种方式都失败，抛出最终异常
          rethrow;
        }
      }
    } catch (e) {
      throw Exception('Failed to download diary: $e');
    }

    // 同步分类
    if (diary.categoryId != null) {
      try {
        final category = await _downloadCategory(diary.categoryId!);
        await IsarUtil.updateACategory(Category()
          ..id = category['id']!
          ..categoryName = category['name']!);
      } catch (e) {
        LogUtil.printInfo(
            'Failed to sync category for diary: $diaryId, Error: $e');
      }
    }

    // 下载资源文件
    diary.imageName = await _downloadFiles(
        diary.imageName, '${WebDavOptions.imagePath}/$diaryId', 'image');
    diary.audioName = await _downloadFiles(
        diary.audioName, '${WebDavOptions.audioPath}/$diaryId', 'audio');
    diary.videoName = await _downloadFiles(
        diary.videoName, '${WebDavOptions.videoPath}/$diaryId', 'video');
    // 下载视频缩略图
    await _downloadFiles(
        diary.videoName, '${WebDavOptions.videoPath}/$diaryId', 'thumbnail');
    return diary;
  }

  Future<List<String>> _downloadFiles(
      List<String> fileNames, String resourcePath, String type) async {
    final localFileNames = <String>[];

    for (final fileName in fileNames) {
      final serverFilePath = type == 'thumbnail'
          ? '$resourcePath/thumbnail-${fileName.substring(6, 42)}.jpeg'
          : '$resourcePath/$fileName';
      final localFilePath = FileUtil.getRealPath(type, fileName);

      try {
        final fileBytes = await _client!.read(serverFilePath);
        final file = File(localFilePath);
        await file.writeAsBytes(fileBytes);
        localFileNames.add(fileName);
        LogUtil.printInfo('$type file downloaded: $fileName');
      } catch (e) {
        LogUtil.printInfo(
            'Failed to download $type file: $fileName, Error: $e');
      }
    }

    return localFileNames;
  }

  Future<void> _uploadCategory(String categoryId, String categoryName) async {
    final categoryPath = '${WebDavOptions.categoryPath}/$categoryId.json';
    final categoryData = jsonEncode({'id': categoryId, 'name': categoryName});

    try {
      _client!.setHeaders({
        'accept-charset': 'utf-8',
        'Content-Type': 'application/json',
      });
      await _client!.write(categoryPath, utf8.encode(categoryData));
      LogUtil.printInfo('Category uploaded: $categoryPath');
    } catch (e) {
      LogUtil.printInfo('Failed to upload category: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> _downloadCategory(String categoryId) async {
    final categoryPath = '${WebDavOptions.categoryPath}/$categoryId.json';

    try {
      final categoryData = await _client!.read(categoryPath);
      final categoryMap =
          jsonDecode(utf8.decode(categoryData)) as Map<String, dynamic>;
      final categoryName = categoryMap['name'] as String;
      LogUtil.printInfo('Category downloaded: $categoryPath');
      return {'id': categoryId, 'name': categoryName};
    } catch (e) {
      LogUtil.printInfo('Failed to download category: $e');
      throw Exception('Category not found: $categoryId');
    }
  }
}
