import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:moodiary/common/models/ai_provider.dart';
import 'package:moodiary/common/values/default_config.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/services/ai_provider_manager.dart';
import 'package:moodiary/utils/webdav_util.dart';

/// 单个 API 连通性检查结果。
///
/// 所有检查都走**真实请求路径**（含鉴权），失败不抛异常，统一收敛成该对象，
/// 供实验室「API 连通性检查」面板逐项展示。
class ApiHealthResult {
  final String name; // 显示名，如「和风天气」「DeepSeek」
  final bool ok;
  final int? statusCode; // HTTP 状态码（WebDAV ping 等无 HTTP 时为 null）
  final int latencyMs; // 耗时（毫秒）
  final String detail; // 人类可读诊断：成功=OK 文案，失败=原因
  final String? raw; // 原始错误摘要（诊断备用）

  ApiHealthResult({
    required this.name,
    required this.ok,
    this.statusCode,
    required this.latencyMs,
    required this.detail,
    this.raw,
  });
}

/// API 连通性检查器 — 逐项测试各服务商的连通性。
///
/// AI 服务商用一次极小 chat（1 段流即判通）、天气/地图/TTS 用 HTTP 首包、
/// WebDAV 用 ping。每项带 15s 兜底超时，永不挂起、永不抛异常。
class ApiHealthService {
  static const Duration _timeout = Duration(seconds: 15);

  /// 检查一个 AI 服务商：真实发起最小 chat，收到第一段流即视为连通。
  static Future<ApiHealthResult> checkAiProvider(AIProviderConfig cfg) async {
    if (cfg.apiKey.isEmpty) {
      return ApiHealthResult(
          name: cfg.displayName,
          ok: false,
          latencyMs: 0,
          detail: '未配置 key（上方编辑填入）');
    }
    final t0 = DateTime.now();
    try {
      final stream = (await AIProviderFactory.create(cfg).chat(
        messages: [AIMessage(role: 'user', content: 'ping')],
      )).timeout(_timeout); // 对整条流设硬超时：推理模型/挂起流也不会无限等待
      await for (final _ in stream) {
        break; // 收到第一段流 = 服务可达且鉴权通过
      }
      final ms = DateTime.now().difference(t0).inMilliseconds;
      return ApiHealthResult(
        name: cfg.displayName,
        ok: true,
        latencyMs: ms,
        detail: '连通（模型 ${cfg.model}）',
      );
    } on TimeoutException {
      return ApiHealthResult(
        name: cfg.displayName,
        ok: false,
        latencyMs: DateTime.now().difference(t0).inMilliseconds,
        detail: '超时（${_timeout.inSeconds}s）',
        raw: '服务器长时间无响应',
      );
    } on DioException catch (e) {
      return ApiHealthResult(
        name: cfg.displayName,
        ok: false,
        statusCode: e.response?.statusCode,
        latencyMs: DateTime.now().difference(t0).inMilliseconds,
        detail: _dioDetail(e),
        raw: e.toString(),
      );
    } catch (e) {
      return ApiHealthResult(
        name: cfg.displayName,
        ok: false,
        latencyMs: DateTime.now().difference(t0).inMilliseconds,
        detail: '$e',
        raw: e.toString(),
      );
    }
  }

  /// 和风天气：实时天气 + geo 城市查询（日记写入实际用的两套接口），
  /// key 与专属 Host 都取 PrefUtil 里用户配置的。
  static Future<ApiHealthResult> checkQweather() async {
    const name = '和风天气';
    final key = PrefUtil.getValue<String>('qweatherKey') ?? '';
    if (key.isEmpty) {
      return ApiHealthResult(
          name: name, ok: false, latencyMs: 0, detail: '未配置 key（实验室填入）');
    }
    // 专属域名下 geo 前缀 /geo；未配 Host 时回落旧公共域名（devapi / geoapi）
    final hasHost =
        (PrefUtil.getValue<String>('qweatherHost') ?? '').trim().isNotEmpty;
    final host = _qweatherHost(fallback: 'devapi.qweather.com');
    final geoHost = hasHost ? host : 'geoapi.qweather.com';
    final geoPath = hasHost ? '/geo/v2/city/lookup' : '/v2/city/lookup';
    final t0 = DateTime.now();
    try {
      final loc = {'location': '116.40,39.90', 'key': key, 'lang': 'zh'};
      // ① 实时天气
      final wRes = await _dio().get(
        'https://$host/v7/weather/now',
        queryParameters: loc,
      );
      final wCode = _qweatherCode(wRes.data);
      // ② geo 城市查询（GPS→城市）
      final gRes = await _dio().get(
        'https://$geoHost$geoPath',
        queryParameters: loc,
      );
      final gCode = _qweatherCode(gRes.data);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      final ok = wRes.statusCode == 200 && wCode == '200' &&
          gRes.statusCode == 200 && gCode == '200';
      return ApiHealthResult(
        name: name,
        ok: ok,
        statusCode: wRes.statusCode,
        latencyMs: ms,
        detail: ok
            ? '连通（天气 code=$wCode · 定位 code=$gCode）'
            : '天气 HTTP ${wRes.statusCode} code=$wCode ${_qweatherHint(wCode)}'
                '；定位 HTTP ${gRes.statusCode} code=$gCode ${_qweatherHint(gCode)}',
        raw: ok ? null : '专属 API Host 填错或未填，会导致天气/定位全挂',
      );
    } on DioException catch (e) {
      return _dioFail(name, e, t0);
    } catch (e) {
      return ApiHealthResult(
          name: name,
          ok: false,
          latencyMs: DateTime.now().difference(t0).inMilliseconds,
          detail: '$e');
    }
  }

  /// 和风专属 API Host（剥协议与尾斜杠）；为空时由调用方按接口回落旧公共域名。
  static String _qweatherHost({required String fallback}) {
    final h = (PrefUtil.getValue<String>('qweatherHost') ?? '').trim();
    if (h.isEmpty) return fallback;
    return h.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/$'), '');
  }

  /// 从和风响应体里取业务 code（HTTP 200 不代表业务成功）。
  static String _qweatherCode(dynamic data) {
    final body = data is Map ? data : const {};
    return body['code']?.toString() ?? '';
  }

  /// 天地图：请求一张矢量底图瓦片，200 即通（鉴权由 tk 参数决定）。
  static Future<ApiHealthResult> checkTianditu() async {
    const name = '天地图';
    final key = PrefUtil.getValue<String>('tiandituKey') ?? '';
    if (key.isEmpty) {
      return ApiHealthResult(
          name: name, ok: false, latencyMs: 0, detail: '未配置 key（实验室填入）');
    }
    final url =
        'https://t6.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile'
        '&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
        '&TILEMATRIX=0&TILEROW=0&TILECOL=0&tk=$key';
    final t0 = DateTime.now();
    try {
      final res = await _dio().get(url);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      final ok = res.statusCode == 200;
      return ApiHealthResult(
        name: name,
        ok: ok,
        statusCode: res.statusCode,
        latencyMs: ms,
        detail: ok
            ? '连通（瓦片请求 200）'
            : 'HTTP ${res.statusCode} ${_httpHint(res.statusCode!)}',
      );
    } on DioException catch (e) {
      return _dioFail(name, e, t0);
    }
  }

  /// 腾讯位置服务 IP 定位（环境感知主通道，零权限城市级定位）。
  static Future<ApiHealthResult> checkTencentIp() async {
    const name = '腾讯位置服务';
    const key = DefaultConfig.tencentIpKey;
    if (key.isEmpty) {
      return ApiHealthResult(
          name: name,
          ok: false,
          latencyMs: 0,
          detail: '未配置（构建注入 MOODIARY_TENCENT_IP_KEY）');
    }
    final t0 = DateTime.now();
    try {
      final res = await _dio().get(
        'https://apis.map.qq.com/ws/location/v1/ip',
        queryParameters: {'key': key},
      );
      final ms = DateTime.now().difference(t0).inMilliseconds;
      final body = res.data is Map ? (res.data as Map) : const {};
      final status = body['status']?.toString() ?? '';
      final msg = body['message']?.toString() ?? '';
      final ok = res.statusCode == 200 && status == '0';
      return ApiHealthResult(
        name: name,
        ok: ok,
        statusCode: res.statusCode,
        latencyMs: ms,
        detail: ok
            ? '连通（定位 status=0）'
            : 'status=$status $msg ${_httpHint(res.statusCode!)}',
      );
    } on DioException catch (e) {
      return _dioFail(name, e, t0);
    } catch (e) {
      return ApiHealthResult(
          name: name,
          ok: false,
          latencyMs: DateTime.now().difference(t0).inMilliseconds,
          detail: '$e');
    }
  }

  /// 豆包语音合成：发一条最小 TTS 请求，读到首个 SSE 事件 code=0 即通。
  static Future<ApiHealthResult> checkDoubaoTts() async {
    const name = '豆包语音合成';
    const key = DefaultConfig.doubaoTtsKey;
    if (key.isEmpty) {
      return ApiHealthResult(
          name: name,
          ok: false,
          latencyMs: 0,
          detail: '未配置（构建注入 MOODIARY_DOUBAO_TTS_KEY）');
    }
    final t0 = DateTime.now();
    try {
      final res = await _dio().post<ResponseBody>(
        'https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse',
        data: jsonEncode({
          'user': {'uid': 'moodiary_health'},
          'req_params': {
            'text': '连通性测试',
            'speaker': 'zh_female_vv_uranus_bigtts',
            'sample_rate': 24000,
            'audio_params': {'format': 'mp3'},
          },
        }),
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            'X-Api-Key': key,
            'X-Api-Resource-Id': 'seed-tts-2.0',
            'X-Api-Request-Id':
                'health_${DateTime.now().millisecondsSinceEpoch}',
          },
        ),
      );
      final lines = res.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      String? code;
      await for (final line in lines) {
        final t = line.trim();
        if (!t.startsWith('data:')) continue;
        try {
          final j = jsonDecode(t.substring(5).trim());
          code = j['code']?.toString();
        } catch (_) {}
        break;
      }
      final ms = DateTime.now().difference(t0).inMilliseconds;
      final ok = code == '0';
      return ApiHealthResult(
        name: name,
        ok: ok,
        statusCode: res.statusCode,
        latencyMs: ms,
        detail: ok
            ? '连通（已开始合成）'
            : 'API code=${code ?? '（无事件）'}（鉴权或音色资源错误）',
      );
    } on DioException catch (e) {
      return _dioFail(name, e, t0);
    } catch (e) {
      return ApiHealthResult(
          name: name,
          ok: false,
          latencyMs: DateTime.now().difference(t0).inMilliseconds,
          detail: '$e');
    }
  }

  /// WebDAV 同步服务器：init 后 ping，报告服务器地址。
  static Future<ApiHealthResult> checkWebDav() async {
    const name = 'WebDAV 同步';
    final opt = PrefUtil.getValue<List<String>>('webDavOption') ?? [];
    if (opt.isEmpty || (opt.firstOrNull?.isEmpty ?? true)) {
      return ApiHealthResult(
          name: name, ok: false, latencyMs: 0, detail: '未配置（设置→数据同步）');
    }
    final base = opt[0];
    final t0 = DateTime.now();
    try {
      await WebDavUtil().initWebDav().timeout(_timeout);
      final ok = await WebDavUtil().checkConnectivity().timeout(_timeout);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      return ApiHealthResult(
        name: name,
        ok: ok,
        latencyMs: ms,
        detail: ok ? '连通（$base）' : 'ping 失败（$base）',
        raw: ok ? null : '服务器不可达或账号密码错误',
      );
    } on TimeoutException {
      return ApiHealthResult(
        name: name,
        ok: false,
        latencyMs: DateTime.now().difference(t0).inMilliseconds,
        detail: '超时（${_timeout.inSeconds}s）',
        raw: '服务器不可达',
      );
    } catch (e) {
      return ApiHealthResult(
          name: name,
          ok: false,
          latencyMs: DateTime.now().difference(t0).inMilliseconds,
          detail: '$e');
    }
  }

  /// 组装要检查的 AI provider 列表：当前生效的那个（助手实际在用的）排最前，
  /// 已配置（apiKey 非空）的其它 provider 依次排后；同源重复项（同 baseUrl+model
  /// 的旧残留，常带过期 key）只留一个。这样「健康检查测的」==「助手对话用的」，
  /// 不会出现检查红、对话却正常这种误导。
  static List<AIProviderConfig> configuredAiProviders() {
    final providersJson = PrefUtil.getValue<String>('aiProviders');
    if (providersJson == null || providersJson.isEmpty) return [];
    final all = <AIProviderConfig>[];
    try {
      for (final e in jsonDecode(providersJson) as List) {
        all.add(AIProviderConfig.fromJson(e as Map<String, dynamic>));
      }
    } catch (_) {
      return [];
    }
    final configured = all.where((c) => c.apiKey.isNotEmpty).toList();
    final current = AiProviderManager().currentProvider;
    final currentCfg = current?.config;

    final result = <AIProviderConfig>[];
    final seen = <String>{};
    void addOnce(AIProviderConfig c) {
      final key = '${c.baseUrl}|${c.model}';
      if (seen.contains(key)) return;
      seen.add(key);
      result.add(c);
    }

    if (currentCfg != null && currentCfg.apiKey.isNotEmpty) addOnce(currentCfg);
    for (final c in configured) {
      if (c.id != currentCfg?.id) addOnce(c);
    }
    return result;
  }

  /// 全部一次跑完：AI 服务商逐个 + 其余服务并发，返回有序结果列表。
  static Future<List<ApiHealthResult>> checkAll() async {
    final tasks = <Future<ApiHealthResult>>[];
    final providers = configuredAiProviders();
    if (providers.isEmpty) {
      tasks.add(Future.value(ApiHealthResult(
          name: 'AI 服务商',
          ok: false,
          latencyMs: 0,
          detail: '未配置任何服务商（实验室添加）')));
    } else {
      for (final cfg in providers) {
        tasks.add(checkAiProvider(cfg));
      }
    }
    tasks.addAll([
      checkQweather(),
      checkTianditu(),
      checkTencentIp(),
      checkDoubaoTts(),
      checkWebDav(),
    ]);
    return await Future.wait(tasks);
  }

  /// 统一 Dio：短超时，避免死 API 长期挂起。
  static Dio _dio() => Dio(BaseOptions(
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        sendTimeout: _timeout,
      ));

  static ApiHealthResult _dioFail(
      String name, DioException e, DateTime t0) {
    return ApiHealthResult(
      name: name,
      ok: false,
      statusCode: e.response?.statusCode,
      latencyMs: DateTime.now().difference(t0).inMilliseconds,
      detail: _dioDetail(e),
      raw: e.toString(),
    );
  }

  /// DioException → 人类可读错误（含 HTTP 状态码含义）。
  static String _dioDetail(DioException e) {
    final sc = e.response?.statusCode;
    if (sc != null) return 'HTTP $sc ${_httpHint(sc)}';
    return switch (e.type) {
      DioExceptionType.connectionTimeout => '连接超时',
      DioExceptionType.sendTimeout => '发送超时',
      DioExceptionType.receiveTimeout => '响应超时',
      DioExceptionType.connectionError => '连接失败（DNS/网络）：${e.message}',
      _ => e.message ?? e.toString(),
    };
  }

  static String _httpHint(int sc) => switch (sc) {
        401 => '（鉴权失败，key 无效）',
        403 => '（无权限，key 被拒/过期）',
        404 => '（接口地址不存在）',
        429 => '（触发限流）',
        500 || 502 || 503 => '（服务端错误）',
        _ => '',
      };

  static String _qweatherHint(String code) => switch (code) {
        '400' => '（请求参数错误）',
        '401' => '（key 无效）',
        '403' => '（key 无权限/过期）',
        '404' => '（接口路径不存在）',
        '429' => '（访问过于频繁）',
        _ => '',
      };
}
