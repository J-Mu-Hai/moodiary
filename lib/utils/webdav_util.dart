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
    await _client!.mkdirAll(WebDavOptions.metaPath);
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

  /// 日记全量同步防重入锁（启动/周期自动同步与手动同步按钮并发时，本次
  /// 直接跳过交给下一轮，避免两个全量同步同时读写服务器 sync.json 造成
  /// 读-改-写竞态丢标记）。
  bool _syncingDiary = false;

  Future<void> syncDiary(
    List<Diary> localDiaries, {
    flutter.VoidCallback? onUpload,
    flutter.VoidCallback? onDownload,
    flutter.VoidCallback? onComplete,
  }) async {
    if (_client == null || _syncingDiary) return;
    _syncingDiary = true;
    try {
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

    // 更新服务器的同步 JSON 文件（无变化时跳过回写，避免每次全量同步
    // 都白写一次服务器文件——自动同步每 5 分钟跑一次时会反复 PUT 同一内容）
    if (!flutter.mapEquals(serverSyncData, updatedSyncData)) {
      await updateServerSyncData(updatedSyncData);
    }
    onComplete?.call();
    } finally {
      _syncingDiary = false;
    }
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
      if (!flutter.mapEquals(serverSyncData, updatedSyncData)) {
        await updateUsageSyncData(updatedSyncData);
      }
      onComplete?.call();
    } finally {
      _syncingUsage = false;
    }
  }

  // ========== 智能体元数据（画像 / 任务 / 聊天记录）同步 ==========

  /// 参与跨端同步的 PrefUtil 元数据键。
  /// 用户输入(assistantChat)、智能体任务(agentTasks/agentRules)、
  /// 用户画像(userMemory)、日记已读侧表(diaryAiRead)、
  /// 大脑输入/输出记录(brainLastDecision/brainDecisionLog)。
  /// 这些键体量小、变化频繁、用户感知强，单独走一条快同步链路，
  /// 不随日记的慢同步。
  static const List<String> _metaKeys = [
    'userMemory',
    'agentTasks',
    'agentRules',
    'assistantChat',
    'diaryAiRead',
    'brainLastDecision',
    'brainDecisionLog',
    // 行为观察时序库 / 专注模式状态（智能体观察者阶段 4）
    'behaviorObservations',
    'focusMode',
    // 统一作息库（daily_rhythm.dart）：起床时间/分时段计划/完成情况
    'dailyRhythm',
  ];

  /// 本地"上次应用的服务器标记"（key → {m: 服务器 mtime, h: 内容指纹}），
  /// 存 PrefUtil。m 用于判断"服务器是否在我上次应用之后又变了"；h 用于
  /// 免下载判断"本地值相对上次应用时是否变了"（见 [_metaFingerprint]）。
  static const String _metaStampKey = 'metaSyncStamp';

  /// 元数据同步防重入锁
  bool _syncingMeta = false;

  /// Meta 目录是否已在本会话中创建（避免每次同步都发一次 mkdirAll）
  bool _metaDirReady = false;

  /// 内容指纹：长度 + FNV-1a（31 位），判断"本地值相对上次应用时是否变了"。
  /// 不依赖 Dart 内置 hashCode（它可能跨 runtime 版本变化，会导致 App
  /// 升级后误判"本地改了"而把旧值推上服务器），保证指纹跨版本稳定。
  /// 只在同一设备上做比较（stamp 按设备本地存储）。
  static String _metaFingerprint(String value) {
    var h = 0x811c9dc5; // FNV offset basis
    for (final u in value.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0x7fffffff; // FNV prime，掩到 31 位避免负号歧义
    }
    return '${value.length}:$h';
  }

  /// 读取本地 stamp。兼容旧格式：旧数据是 `key → mtime 字符串`，迁到
  /// 新格式时指纹置 null，同步时会走一次内容对比后补上新指纹。
  Map<String, Map<String, dynamic>> _getMetaStamp() {
    final s = PrefUtil.getValue<String>(_metaStampKey);
    if (s == null || s.isEmpty) return {};
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return {};
      final result = <String, Map<String, dynamic>>{};
      decoded.forEach((k, v) {
        if (v is String) {
          // 旧格式：只有 mtime，内容未知 → 下一轮做内容对比
          result[k.toString()] = {'m': v, 'h': null};
        } else if (v is Map) {
          result[k.toString()] = Map<String, dynamic>.from(v);
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> _touchMetaStamp(String key, String mtime, [String? fingerprint]) async {
    final map = _getMetaStamp();
    map[key] = {'m': mtime, 'h': fingerprint};
    await PrefUtil.setValue<String>(_metaStampKey, jsonEncode(map));
  }

  Future<Map<String, String>> _fetchMetaSyncData() async {
    if (_client == null) return {};
    try {
      final response = await _client!
          .read(WebDavOptions.metaSyncFlagPath)
          .timeout(const Duration(seconds: 15));
      if (response.isNotEmpty) {
        return Map<String, String>.from(jsonDecode(utf8.decode(response)));
      }
    } catch (_) {
      // 标记文件尚未创建，视为空
    }
    return {};
  }

  Future<void> _updateMetaSyncData(Map<String, String> syncData) async {
    if (_client == null) return;
    await _client!
        .write(WebDavOptions.metaSyncFlagPath, utf8.encode(jsonEncode(syncData)))
        .timeout(const Duration(seconds: 15));
  }

  Future<void> _writeMetaKey(String key, String value) async {
    _client!.setHeaders({
      'accept-charset': 'utf-8',
      'Content-Type': 'application/json',
    });
    await _client!
        .write('${WebDavOptions.metaPath}/$key.json', utf8.encode(value))
        .timeout(const Duration(seconds: 15));
  }

  /// 智能体元数据的双向增量同步（手机 ↔ 电脑）。
  ///
  /// 与 [syncDiary]/[syncUsageRecords] 同一套"同步标记 + 逐条 JSON"范式，
  /// 独立目录 `/Moodiary/Meta/`：`sync.json` 记录每个键最后写入时刻，
  /// `<key>.json` 存对应 PrefUtil 键的 JSON 值。画像 / 任务 / 聊天记录
  /// 体量小，同步快，随"发消息即时推送 + 聊天页 10 秒轮询 + 应用启动 +
  /// 5 分钟采集"等节奏同步，秒级到达另一端。
  ///
  /// [pullOnly] 为轻量轮询模式（聊天页定时器用）：只拉取"服务器在我上次
  /// 应用之后又变了"的键，不推、不改服务器标记，每次只 1~2 个小请求，
  /// 适合高频轮询。推送由发消息/离开页面等完整同步负责。
  ///
  /// 完整同步对每个键：本地/服务器都有且内容未变时，凭「上次内容指纹」
  /// （见 [_metaFingerprint]，存于本地 stamp）免下载直接跳过——即使
  /// 元数据键变大了（如完整的大脑输入/输出日志）也不会拖慢每次同步。
  ///
  /// 冲突策略（v1）：按键 last-write-wins。
  /// - 本地无值且服务器有 → 拉取；
  /// - 本地有且服务器无 → 推送；
  /// - 两边都有：服务器自上次应用后没变 → 本地改了推、没改跳过；
  ///   服务器在我之后变了 → 拉取服务器。
  /// 单一用户交替使用手机/电脑的场景足够，不做字段级合并。
  Future<void> syncMetadata({
    bool pullOnly = false,
    flutter.VoidCallback? onUpload,
    flutter.VoidCallback? onDownload,
    flutter.VoidCallback? onComplete,
  }) async {
    if (_client == null || _syncingMeta) return;
    _syncingMeta = true;
    try {
      if (!_metaDirReady) {
        await _client!.mkdirAll(WebDavOptions.metaPath);
        _metaDirReady = true;
      }
      final serverFlag = await _fetchMetaSyncData();
      final stamp = _getMetaStamp();
      final updatedFlag = {...serverFlag};

      for (final key in _metaKeys) {
        final local = PrefUtil.getValue<String>(key);
        final serverMtime = serverFlag[key];
        final stampEntry = stamp[key];
        final lastMtime = stampEntry?['m'] as String?;
        final lastFp = stampEntry?['h'] as String?;

        // 轮询模式：只拉取"服务器在我上次应用后变了"的键（含本地还没有、
        // 服务器却有的情况），不推、不改服务器标记。
        if (pullOnly) {
          final remoteChanged = serverMtime != null && lastMtime != serverMtime;
          if (!remoteChanged) continue;
          try {
            final data = await _client!
                .read('${WebDavOptions.metaPath}/$key.json')
                .timeout(const Duration(seconds: 15));
            if (data.isNotEmpty) {
              final pulled = utf8.decode(data);
              await PrefUtil.setValue<String>(key, pulled);
              onDownload?.call();
              await _touchMetaStamp(key, serverMtime, _metaFingerprint(pulled));
            } else {
              await _touchMetaStamp(key, serverMtime, lastFp);
            }
          } catch (_) {
            // 单次拉取失败不处理，下一轮再试
          }
          continue;
        }

        // 本地没有值：服务器有就拉一份，两边都没有就跳过。
        if (local == null || local.isEmpty) {
          if (serverMtime == null) continue;
          try {
            final data = await _client!
                .read('${WebDavOptions.metaPath}/$key.json')
                .timeout(const Duration(seconds: 15));
            if (data.isNotEmpty) {
              final pulled = utf8.decode(data);
              await PrefUtil.setValue<String>(key, pulled);
              onDownload?.call();
              await _touchMetaStamp(key, serverMtime, _metaFingerprint(pulled));
            }
          } catch (e) {
            // 下载失败，移除标记避免反复尝试
            updatedFlag.remove(key);
          }
          continue;
        }

        // 本地有、服务器没有 → 推送本地。
        if (serverMtime == null) {
          await _writeMetaKey(key, local);
          final pushed = DateTime.now().toIso8601String();
          updatedFlag[key] = pushed;
          await _touchMetaStamp(key, pushed, _metaFingerprint(local));
          onUpload?.call();
          continue;
        }

        // 两边都有。优先用「上次内容指纹 + 服务器 mtime」判断，避免每次
        // 全量同步都把（可能较大的）元数据从服务器下载下来做内容对比。
        // 旧格式 stamp（指纹为 null）时退回老的内容对比逻辑做一次迁移。
        if (lastFp != null) {
          if (lastMtime == serverMtime) {
            // 服务器自上次应用后没变：本地还是上次那份就无变化；本地改了
            // 则直接推送（无需下载，本地值就是最新）。
            if (_metaFingerprint(local) == lastFp) {
              await _touchMetaStamp(key, serverMtime, lastFp);
              continue;
            }
            await _writeMetaKey(key, local);
            final pushed = DateTime.now().toIso8601String();
            updatedFlag[key] = pushed;
            await _touchMetaStamp(key, pushed, _metaFingerprint(local));
            onUpload?.call();
            continue;
          }
          // 服务器在我之后变了 → 拉取服务器版本（last-write-wins）。
          String? pulled;
          try {
            final data = await _client!
                .read('${WebDavOptions.metaPath}/$key.json')
                .timeout(const Duration(seconds: 15));
            if (data.isNotEmpty) {
              pulled = utf8.decode(data);
              await PrefUtil.setValue<String>(key, pulled);
              onDownload?.call();
            }
          } catch (_) {
            // 拉取失败保留本地值，下一轮再试
          }
          await _touchMetaStamp(
              key, serverMtime, _metaFingerprint(pulled ?? local));
          continue;
        }

        // 迁移路径（旧 stamp 无指纹）：读服务器内容对比，决定推/拉，落新指纹。
        String? serverData;
        try {
          final data = await _client!
              .read('${WebDavOptions.metaPath}/$key.json')
              .timeout(const Duration(seconds: 15));
          serverData = data.isNotEmpty ? utf8.decode(data) : null;
        } catch (_) {
          serverData = null;
        }

        if (serverData == local) {
          // 内容一致：采纳当前标记即可，不重复上传。
          await _touchMetaStamp(key, serverMtime, _metaFingerprint(local));
          continue;
        }

        if (lastMtime == serverMtime) {
          // 服务器在我上次应用后没变，本地改了 → 推送本地。
          await _writeMetaKey(key, local);
          final pushed = DateTime.now().toIso8601String();
          updatedFlag[key] = pushed;
          await _touchMetaStamp(key, pushed, _metaFingerprint(local));
          onUpload?.call();
        } else {
          // 服务器在我之后变了 → 拉取服务器版本（last-write-wins）。
          if (serverData != null) {
            await PrefUtil.setValue<String>(key, serverData);
            onDownload?.call();
          }
          await _touchMetaStamp(
              key, serverMtime, _metaFingerprint(serverData ?? local));
        }
      }

      // 轮询模式不改服务器标记（只读）；完整同步只在有变化时才写回。
      if (!pullOnly &&
          !flutter.mapEquals(serverFlag, updatedFlag)) {
        await _updateMetaSyncData(updatedFlag);
      }
      onComplete?.call();
    } catch (e) {
      print('[SYNC] metadata sync error: $e');
    } finally {
      _syncingMeta = false;
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
