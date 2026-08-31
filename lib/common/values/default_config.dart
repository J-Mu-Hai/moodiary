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

  // ── 环境感知与语音（构建注入，默认空）──
  // 和风天气 key（实时天气 + 城市查询），也会预填进 PrefUtil 供现有天气模块复用
  static const String qweatherKey =
      String.fromEnvironment('MOODIARY_QWEATHER_KEY');
  // 和风天气专属 API Host（2026 起旧公共域名 devapi/api/geoapi.qweather.com
  // 逐步停用，key 绑定个人专属域名，如 abc123.def.qweatherapi.com）。
  // 未注入/为空时调用方回落到旧公共域名（兼容老配置）。
  static const String qweatherHost =
      String.fromEnvironment('MOODIARY_QWEATHER_HOST');
  // 腾讯位置服务 IP 定位 key（城市级定位，零权限）
  static const String tencentIpKey =
      String.fromEnvironment('MOODIARY_TENCENT_IP_KEY');
  // 豆包语音合成 key（文本转语音）
  static const String doubaoTtsKey =
      String.fromEnvironment('MOODIARY_DOUBAO_TTS_KEY');
  // 天地图 key（地图/地理编码等地理服务），也会预填进 PrefUtil 供现有设置复用
  static const String tiandituKey =
      String.fromEnvironment('MOODIARY_TIANDITU_KEY');

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

    // 2. AI Provider：无 provider 且注入了 DeepSeek key 才预填；
    //    已有默认 provider 但注入的 key/baseUrl/model 变化（.env.local 轮换）
    //    → 同步更新。否则旧 key 会一直留在手机上，构建注入的新 key 被忽略，
    //    旧 key 失效后所有 AI 调用都 401。
    final providersJson = PrefUtil.getValue<String>('aiProviders');
    if (deepSeekApiKey.isNotEmpty) {
      final config = AIProviderConfig(
        id: 'provider_default_deepseek',
        displayName: 'DeepSeek',
        baseUrl: deepSeekBaseUrl,
        apiKey: deepSeekApiKey,
        model: deepSeekModel,
        maxTokens: deepSeekMaxTokens,
      );
      final list = <AIProviderConfig>[];
      if (providersJson != null && providersJson.isNotEmpty) {
        try {
          for (final e in jsonDecode(providersJson) as List) {
            list.add(AIProviderConfig.fromJson(e as Map<String, dynamic>));
          }
        } catch (e) {
          print('[DefaultConfig] 解析 aiProviders 失败: $e');
        }
      }
      var changed = false;
      final idx = list.indexWhere((c) => c.id == config.id);
      if (idx < 0) {
        list.add(config);
        changed = true;
      } else if (list[idx].apiKey != config.apiKey ||
          list[idx].baseUrl != config.baseUrl ||
          list[idx].model != config.model) {
        list[idx] = config;
        changed = true;
      }
      if (changed) {
        await PrefUtil.setValue<String>(
          'aiProviders',
          jsonEncode(list.map((e) => e.toJson()).toList()),
        );
      }
      // 当前选中的 provider：
      //   - 为空 / 指向不存在 → 归位到默认
      //   - 与默认 DeepSeek 同源（同 baseUrl）但 key 不是注入的最新 key
      //     → 说明是旧 key 残留的手动重复项，key 已失效（401），也归位到默认
      //   - 用户手动选的其它服务商（不同 baseUrl）→ 尊重，保留
      final currentId = PrefUtil.getValue<String>('aiCurrentProviderId') ?? '';
      AIProviderConfig? currentCfg;
      for (final c in list) {
        if (c.id == currentId) {
          currentCfg = c;
          break;
        }
      }
      final sameOriginStale = currentCfg != null &&
          currentCfg.id != config.id &&
          currentCfg.baseUrl == config.baseUrl &&
          currentCfg.apiKey != config.apiKey;
      if (currentCfg == null || sameOriginStale) {
        await PrefUtil.setValue<String>('aiCurrentProviderId', config.id);
      }
      // 诊断：打印实际生效的 provider 列表（key 脱敏），便于从日志排查 401
      print('[DefaultConfig] AI providers='
          '${list.map((c) => '${c.id}:${_maskKey(c.apiKey)}').join(' | ')}');
    }

    // 3. 和风天气 key：未配置且构建时注入了才预填；已配置但被构建注入的新 key
    //    顶替（.env.local 轮换）→ 同步更新，否则旧 key 一直留着、新 key 失效
    //    后所有天气调用 403/401（与 AI provider 同款同步策略）。
    final existingQweatherKey = PrefUtil.getValue<String>('qweatherKey');
    if (qweatherKey.isNotEmpty) {
      if (existingQweatherKey == null || existingQweatherKey.isEmpty) {
        await PrefUtil.setValue<String>('qweatherKey', qweatherKey);
      } else if (existingQweatherKey != qweatherKey) {
        await PrefUtil.setValue<String>('qweatherKey', qweatherKey);
        print('[DefaultConfig] 和风天气 key 已同步为构建注入的新 key');
      }
    }

    // 3b. 和风专属 API Host：未配置且构建时注入了才预填（环境感知/天气/定位复用）
    final existingQweatherHost = PrefUtil.getValue<String>('qweatherHost');
    if ((existingQweatherHost == null || existingQweatherHost.isEmpty) &&
        qweatherHost.isNotEmpty) {
      await PrefUtil.setValue<String>('qweatherHost', qweatherHost);
    }

    // 4. 天地图 key：未配置且构建时注入了才预填
    final existingTiandituKey = PrefUtil.getValue<String>('tiandituKey');
    if ((existingTiandituKey == null || existingTiandituKey.isEmpty) &&
        tiandituKey.isNotEmpty) {
      await PrefUtil.setValue<String>('tiandituKey', tiandituKey);
    }
  }

  /// 脱敏 key：只显示前 8 位与长度，日志可安全携带。
  static String _maskKey(String key) => key.isEmpty
      ? '(空)'
      : '${key.length > 8 ? key.substring(0, 8) : key}…(${key.length})';
}
