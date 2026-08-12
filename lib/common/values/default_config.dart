import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/pref.dart';

/// 个人默认配置（临时硬编码，每次编译/安装后自动预填，免手动填写）。
///
/// ⚠️ 注意：这里的 DeepSeek API Key 与 WebDAV 密码是明文写死在代码里的，
/// 只适合个人自用的安装包，切勿对外发布。若日后要上架，必须移除此文件
/// 的种子逻辑，改回手动填写。
class DefaultConfig {
  // ── WebDAV 同步服务器 ──
  static const String webDavBaseUrl = 'http://REPLACED_HOST_000000:6060/';
  static const String webDavUsername = 'REPLACED_USER';
  static const String webDavPassword = 'REPLACED_PASSWORD_00000000';

  // ── DeepSeek ──
  static const String deepSeekBaseUrl = 'https://api.deepseek.com';
  static const String deepSeekApiKey = 'sk-REPLACED_00000000000000000000000000000000';
  static const String deepSeekModel = 'deepseek-v4-flash';
  static const int deepSeekMaxTokens = 4096;

  /// 启动时预填默认配置：WebDAV 三件套 + DeepSeek provider。
  ///
  /// 仅在对应配置为空时才写入，不覆盖用户已有的配置。
  /// 在 [main] 的 `PrefUtil.initPref()` 之后调用。
  static Future<void> seed() async {
    // 1. WebDAV：未配置时预填
    final webDavOption = PrefUtil.getValue<List<String>>('webDavOption') ?? [];
    if (webDavOption.isEmpty) {
      await PrefUtil.setValue(
        'webDavOption',
        [webDavBaseUrl, webDavUsername, webDavPassword],
      );
    }

    // 2. AI Provider：没有任何 provider 时预填 DeepSeek
    final providersJson = PrefUtil.getValue<String>('aiProviders');
    if (providersJson == null || providersJson.isEmpty) {
      final config = AIProviderConfig(
        id: 'provider_default_deepseek',
        displayName: 'DeepSeek',
        baseUrl: deepSeekBaseUrl,
        apiKey: deepSeekApiKey,
        model: deepSeekModel,
        maxTokens: deepSeekMaxTokens,
      );
      await PrefUtil.setValue<String>(
        'aiProviders',
        jsonEncode([config.toJson()]),
      );
      await PrefUtil.setValue<String>('aiCurrentProviderId', config.id);
    }
  }
}
