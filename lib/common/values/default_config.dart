import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/pref.dart';

/// 个人默认配置（构建时从 `--dart-define` 注入，仅在对应配置为空时写入）。
///
/// 敏感信息（WebDAV 服务器/用户名/密码、DeepSeek API Key）**不写死在代码里**，
/// 而是通过 `String.fromEnvironment` 在构建时注入。真实值存放在项目根目录的
/// `.env.local`（已被 .gitignore 排除，不会上传到 GitHub），由 `tool/` 下的
/// 构建脚本自动读取并拼成 `--dart-define` 参数。
///
/// 修改这些敏感值：编辑 `.env.local` 后重新用脚本构建即可，无需改代码。
///
/// 未注入任何值时（例如他人 clone 了公开仓库直接构建），`seed()` 不会预填，
/// 用户走 App 内手动配置流程。
class DefaultConfig {
  // ── WebDAV 同步服务器（构建注入，默认空）──
  static const String webDavBaseUrl =
      String.fromEnvironment('MOODIARY_WEBDAV_URL');
  static const String webDavUsername =
      String.fromEnvironment('MOODIARY_WEBDAV_USERNAME');
  static const String webDavPassword =
      String.fromEnvironment('MOODIARY_WEBDAV_PASSWORD');

  // ── DeepSeek ──
  static const String deepSeekBaseUrl = 'https://api.deepseek.com';
  static const String deepSeekApiKey =
      String.fromEnvironment('MOODIARY_DEEPSEEK_KEY');
  static const String deepSeekModel = 'deepseek-v4-flash';
  static const int deepSeekMaxTokens = 4096;

  /// 启动时预填默认配置：WebDAV 三件套 + DeepSeek provider。
  ///
  /// 仅在对应配置为空时才写入，不覆盖用户已有的配置。
  /// 在 [main] 的 `PrefUtil.initPref()` 之后调用。
  static Future<void> seed() async {
    // 1. WebDAV：未配置且构建时注入了完整三件套才预填
    final webDavOption = PrefUtil.getValue<List<String>>('webDavOption') ?? [];
    if (webDavOption.isEmpty &&
        webDavBaseUrl.isNotEmpty &&
        webDavUsername.isNotEmpty &&
        webDavPassword.isNotEmpty) {
      await PrefUtil.setValue(
        'webDavOption',
        [webDavBaseUrl, webDavUsername, webDavPassword],
      );
    }

    // 2. AI Provider：没有任何 provider 且注入了 DeepSeek key 才预填
    final providersJson = PrefUtil.getValue<String>('aiProviders');
    if ((providersJson == null || providersJson.isEmpty) &&
        deepSeekApiKey.isNotEmpty) {
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
