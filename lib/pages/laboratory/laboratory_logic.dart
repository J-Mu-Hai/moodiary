import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/utils/aes_util.dart';
import 'package:moodiary/utils/environment_sensor.dart';
import 'package:moodiary/utils/file_util.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:moodiary/utils/tts_speaker.dart';
import 'package:refreshed/refreshed.dart';
import 'package:share_plus/share_plus.dart';

class LaboratoryLogic extends GetxController {
  // ─── AI Provider 管理 ─────────────────────────────────

  /// 获取所有 AI Provider 配置
  List<AIProviderConfig> getProviders() {
    final json = PrefUtil.getValue<String>('aiProviders');
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => AIProviderConfig.fromJson(e)).toList();
  }

  /// 保存 AI Provider 配置列表
  Future<void> _saveProviders(List<AIProviderConfig> providers) async {
    final json = jsonEncode(providers.map((p) => p.toJson()).toList());
    await PrefUtil.setValue<String>('aiProviders', json);
    update();
  }

  /// 添加 Provider
  Future<void> addProvider(AIProviderConfig config) async {
    final providers = getProviders();
    // 自动生成唯一 ID
    config.id = 'provider_${DateTime.now().millisecondsSinceEpoch}';
    providers.add(config);
    await _saveProviders(providers);
  }

  /// 更新 Provider
  Future<void> updateProvider(String id, AIProviderConfig config) async {
    final providers = getProviders();
    final index = providers.indexWhere((p) => p.id == id);
    if (index != -1) {
      providers[index] = config;
      await _saveProviders(providers);
    }
  }

  /// 删除 Provider
  Future<void> deleteProvider(String id) async {
    final providers = getProviders();
    providers.removeWhere((p) => p.id == id);
    await _saveProviders(providers);
    // 如果删除的是当前选中的，重置
    if (PrefUtil.getValue<String>('aiCurrentProviderId') == id) {
      await PrefUtil.setValue<String>('aiCurrentProviderId', '');
    }
  }

  // ─── 兼容旧的腾讯云密钥 ───────────────────────────────

  Future<void> setTencentID({required String id, required String key}) async {
    await PrefUtil.setValue<String>('tencentId', id);
    await PrefUtil.setValue<String>('tencentKey', key);
    // 同时也创建一个 TencentProvider
    final providers = getProviders();
    final existing = providers.indexWhere((p) => p.id == 'tencent');
    final config = AIProviderConfig(
      id: 'tencent',
      displayName: '腾讯混元',
      baseUrl: 'https://hunyuan.tencentcloudapi.com',
      model: 'hunyuan-lite',
      apiKey: '$id:$key',
    );
    if (existing != -1) {
      providers[existing] = config;
    } else {
      providers.add(config);
    }
    await _saveProviders(providers);
    update();
  }

  Future<void> setQweatherKey({required String key}) async {
    await PrefUtil.setValue<String>('qweatherKey', key);
    update();
  }

  Future<void> setTiandituKey({required String key}) async {
    await PrefUtil.setValue<String>('tiandituKey', key);
    update();
  }

  Future<void> exportErrorLog() async {
    if ((await File(FileUtil.getErrorLogPath()).readAsString()).isNotEmpty) {
      final result = await Share.shareXFiles([XFile(FileUtil.getErrorLogPath())]);
      if (result.status == ShareResultStatus.success) {
        await File(FileUtil.getErrorLogPath()).writeAsString('');
        NoticeUtil.showToast('日志导出成功，已删除本地日志');
      }
    } else {
      NoticeUtil.showToast('暂无日志');
    }
  }

  Future<bool> aesTest() async {
    final key = await AesUtil.deriveKey(salt: 'salt', userKey: 'password');
    final encrypted = await AesUtil.encrypt(key: key, data: 'Hello World');
    final decrypted = await AesUtil.decrypt(key: key, encryptedData: encrypted);
    return decrypted == 'Hello World';
  }

  // ─── 环境感知 + 语音播报（演示） ─────────────────────

  /// 获取环境快照 → 生成播报句 → 豆包 TTS 合成并播放
  Future<void> environmentBroadcast() async {
    NoticeUtil.showToast('正在获取环境…');
    try {
      final snap = await EnvironmentSensor.getSnapshot();
      if (snap == null) {
        NoticeUtil.showToast('环境获取失败：请检查网络或 key 配置');
        return;
      }
      final p = snap['province'].toString();
      final c = snap['city'].toString();
      final d = snap['district'].toString();
      final city = '$p${(c.isNotEmpty && !p.contains(c) ? c : '')}$d';
      final weather = snap['weather'].toString();
      final temp = snap['temp'].toString();
      final sentence = weather.isNotEmpty
          ? '你现在在$city，天气$weather，$temp 摄氏度。'
          : '你现在在$city。';
      NoticeUtil.showToast('正在合成语音…');
      final ok = await TtsSpeaker.speak(sentence);
      NoticeUtil.showToast(
          ok ? '播放完成' : '语音播放失败: ${TtsSpeaker.lastError}');
    } catch (e) {
      NoticeUtil.showToast('环境播报失败：$e');
    }
  }
}
