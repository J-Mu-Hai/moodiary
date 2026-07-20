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

    // 优先用当前 ID，否则用第一个
    AIProviderConfig targetConfig;
    if (currentId.isNotEmpty) {
      targetConfig = configs.cast<AIProviderConfig?>().firstWhere(
            (c) => c!.id == currentId,
            orElse: () => configs.first,
          )!;
    } else {
      // 没设置过 ID，自动选第一个并保存
      targetConfig = configs.first;
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
