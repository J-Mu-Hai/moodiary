import 'dart:convert';

import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/presentation/pref.dart';

/// AI Provider 管理器 — 从配置获取当前 AI Provider
class AiProviderManager {
  AIProvider? _cachedProvider;
  String? _cachedId;

  /// 获取当前 AI Provider（自动选第一个可用）
  AIProvider? get currentProvider {
    final providersJson = PrefUtil.getValue<String>('aiProviders');
    if (providersJson == null || providersJson.isEmpty) return null;

    final list = jsonDecode(providersJson) as List;
    final configs = list.map((e) => AIProviderConfig.fromJson(e)).toList();
    if (configs.isEmpty) return null;

    final currentId = PrefUtil.getValue<String>('aiCurrentProviderId') ?? '';

    // 优先用当前 ID；否则回退到默认 DeepSeek provider（构建注入 key 的那个）。
    // 不能用 configs.first 兜底：手动加的旧 provider 可能排在最前，
    // 会在没显式选择时被静默顶成当前，导致 key 过期 401。
    AIProviderConfig? defaultCfg;
    for (final c in configs) {
      if (c.id == 'provider_default_deepseek') {
        defaultCfg = c;
        break;
      }
    }
    AIProviderConfig targetConfig;
    if (currentId.isNotEmpty) {
      targetConfig = configs.cast<AIProviderConfig?>().firstWhere(
            (c) => c!.id == currentId,
            orElse: () => defaultCfg ?? configs.first,
          )!;
    } else {
      targetConfig = defaultCfg ?? configs.first;
      PrefUtil.setValue<String>('aiCurrentProviderId', targetConfig.id);
    }

    // 缓存
    if (_cachedId != targetConfig.id || _cachedProvider == null) {
      _cachedProvider = AIProviderFactory.create(targetConfig);
      _cachedId = targetConfig.id;
    }
    return _cachedProvider;
  }
}
