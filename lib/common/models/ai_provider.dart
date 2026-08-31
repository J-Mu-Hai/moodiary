import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:moodiary/utils/log_util.dart';
import 'package:moodiary/utils/signature_util.dart';

/// 一次对话中的单条消息
class AIMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;

  /// 消息时间（默认发送时刻；聊天记录持久化后恢复）
  final DateTime time;

  AIMessage({required this.role, required this.content, DateTime? time})
      : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() =>
      {'role': role, 'content': content, 'time': time.toIso8601String()};
}

/// AI 提供商的配置
class AIProviderConfig {
  String id; // 唯一标识
  String displayName;
  String baseUrl;
  String apiKey;
  String model;
  int maxTokens;

  AIProviderConfig({
    required this.id,
    this.displayName = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.maxTokens = 4096,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'maxTokens': maxTokens,
      };

  factory AIProviderConfig.fromJson(Map<String, dynamic> json) =>
      AIProviderConfig(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
        maxTokens: json['maxTokens'] as int? ?? 4096,
      );

  AIProviderConfig copyWith({
    String? displayName,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? maxTokens,
  }) =>
      AIProviderConfig(
        id: id,
        displayName: displayName ?? this.displayName,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        maxTokens: maxTokens ?? this.maxTokens,
      );
}

/// ============================================================
/// AI Provider 抽象接口
/// ============================================================
abstract class AIProvider {
  AIProviderConfig get config;

  bool get isConfigured => config.apiKey.isNotEmpty && config.baseUrl.isNotEmpty;

  String get displayName => config.displayName;

  /// 发起流式对话请求，返回内容流
  Future<Stream<String>> chat({
    required List<AIMessage> messages,
    String? modelOverride,
  });
}

/// ============================================================
/// Tencent 腾讯混云实现
/// ============================================================
class TencentProvider extends AIProvider {
  @override
  final AIProviderConfig config;

  TencentProvider({required this.config});

  /// Tencent 模型名映射（兼容原有的 int 索引）
  static const models = [
    'hunyuan-lite',
    'hunyuan-standard',
    'hunyuan-pro',
    'hunyuan-turbo',
  ];

  @override
  Future<Stream<String>> chat({
    required List<AIMessage> messages,
    String? modelOverride,
  }) async {
    final model = modelOverride ?? config.model;
    final id = config.apiKey; // tencentId
    final key = ''; // tencentKey 不走 config.apiKey
    // Tencent 的 id/key 是分开存的，从 config.apiKey 解析
    final parts = config.apiKey.split(':');
    final tencentId = parts.isNotEmpty ? parts[0] : '';
    final tencentKey = parts.length > 1 ? parts[1] : '';

    if (tencentId.isEmpty || tencentKey.isEmpty) {
      throw Exception('腾讯云配置不完整，需要 SecretId:SecretKey');
    }

    final bodyMap = {
      'Model': model,
      'Messages': messages.map((m) => m.toJson()).toList(),
      'Stream': true,
    };
    final body = jsonEncode(bodyMap);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sig = SignatureUtil.generateSignature(
      tencentId,
      tencentKey,
      timestamp,
      bodyMap,
    );

    final headers = {
      'Content-Type': 'application/json',
      'X-TC-Action': 'ChatCompletions',
      'X-TC-Timestamp': timestamp.toString(),
      'X-TC-Version': '2023-09-01',
      'Authorization': sig,
    };

    final dio = Dio();
    final Response<ResponseBody> response;
    try {
      response = await dio.post<ResponseBody>(
        config.baseUrl,
        data: body,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );
    } catch (e) {
      _logAIFailure('Tencent', config.baseUrl, model, e);
      rethrow;
    }

    return response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data: '))
        .map((line) {
          try {
            final json = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              if (delta != null && delta['content'] != null) {
                return delta['content'] as String;
              }
            }
          } catch (_) {}
          return '';
        })
        .where((s) => s.isNotEmpty);
  }
}

/// ============================================================
/// OpenAI 兼容实现（OpenAI / DeepSeek / 任意兼容接口）
/// ============================================================
class OpenAICompatibleProvider extends AIProvider {
  @override
  final AIProviderConfig config;

  OpenAICompatibleProvider({required this.config});

  @override
  Future<Stream<String>> chat({
    required List<AIMessage> messages,
    String? modelOverride,
  }) async {
    final model = modelOverride ?? config.model;
    final body = jsonEncode({
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true,
      'max_tokens': config.maxTokens,
    });

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };

    // 自动补全 /chat/completions
    var url = config.baseUrl;
    if (!url.endsWith('/chat/completions')) {
      url = url.replaceAll(RegExp(r'/?$'), '/chat/completions');
    }
    final dio = Dio();
    final Response<ResponseBody> response;
    try {
      response = await dio.post<ResponseBody>(
        url,
        data: body,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 120),
          validateStatus: (status) => status == 200,
        ),
      );
    } catch (e) {
      _logAIFailure('OpenAICompatible', url, model, e);
      rethrow;
    }

    return response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith('data: ') && line != 'data: [DONE]')
        .map((line) {
          try {
            final json = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              if (delta != null && delta['content'] != null) {
                return delta['content'] as String;
              }
            }
          } catch (_) {}
          return '';
        })
        .where((s) => s.isNotEmpty);
  }
}

/// ============================================================
/// Provider 工厂：根据配置创建对应的 Provider 实例
/// ============================================================
class AIProviderFactory {
  static AIProvider create(AIProviderConfig config) {
    switch (config.id) {
      case 'tencent':
        return TencentProvider(config: config);
      case 'openai':
      default:
        return OpenAICompatibleProvider(config: config);
    }
  }

  /// 预设的 Provider 模板
  static List<AIProviderConfig> get presets => [
        AIProviderConfig(
          id: 'tencent',
          displayName: '腾讯混元',
          baseUrl: 'https://hunyuan.tencentcloudapi.com',
          model: 'hunyuan-lite',
          apiKey: '',
        ),
        AIProviderConfig(
          id: 'openai',
          displayName: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1/chat/completions',
          model: 'gpt-3.5-turbo',
          apiKey: '',
        ),
        AIProviderConfig(
          id: 'openai',
          displayName: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/chat/completions',
          model: 'deepseek-chat',
          apiKey: '',
        ),
        AIProviderConfig(
          id: 'openai',
          displayName: '硅基流动',
          baseUrl: 'https://api.siliconflow.cn/v1/chat/completions',
          model: 'THUDM/glm-4-9b-chat',
          apiKey: '',
        ),
      ];
}

/// AI 请求失败诊断：把「最终请求的完整地址 + 状态码」写进日志（debug→控制台，
/// release→error.log，不弹 bug 窗）。DioException 的 toString 不带 URL，
/// 之前 404 只能猜是哪个服务商；加这一行后下次失败能精确定位到具体地址。
void _logAIFailure(String kind, String url, String model, Object e) {
  final status = e is DioException ? e.response?.statusCode : null;
  final msg = status != null
      ? '[AI $kind] 请求失败 $url model=$model → HTTP $status: $e'
      : '[AI $kind] 请求失败 $url model=$model: $e';
  LogUtil.logToFile(msg);
}
