import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:moodiary/common/models/weather.dart';
import 'package:moodiary/common/values/default_config.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/utils/http_util.dart';

/// 环境感知：IP 定位 → 城市 → 和风实时天气。
///
/// 主通道为腾讯位置服务 IP 定位（零权限、城市级），天气用和风按经纬度查询。
/// 腾讯失败时兜底走免 key 的 ip-api.com（http，中文，45 次/分钟）。
/// 返回结构化快照，供智能体函数 `env_snapshot` 与环境播报使用。
class EnvironmentSensor {
  /// 获取环境快照。失败返回 null。
  ///
  /// 全程静默（HttpUtil 静默模式）：这是后台感知，网络/密钥失败不该
  /// 弹「Network Error」toast 打扰用户——调用方自行处理 null。
  static Future<Map<String, dynamic>?> getSnapshot() async {
    return HttpUtil.withQuiet(_fetch);
  }

  /// 地点覆盖（智能体 `set_user_location` 写入）：用户/智能体修正过的省市区。
  /// IP 定位的行政区名不精确（海淀可能被识别成西城），对话中发现用户明确
  /// 说出所在地后由智能体写入覆盖值，之后所有环境快照都以它为准。
  ///
  /// 公开只读入口：ai_functions.dart 的 set_user_location 读旧值做增量合并
  /// （缺省的维度沿用旧值），避免智能体只说「海淀」把省市覆盖成空。
  static Map<String, String>? get overrideValue => _override;

  static Map<String, String>? get _override {
    final s = PrefUtil.getValue<String>('locationOverride');
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map;
      final result = <String, String>{
        'province': m['province']?.toString() ?? '',
        'city': m['city']?.toString() ?? '',
        'district': m['district']?.toString() ?? '',
      };
      return (result['province']!.isEmpty &&
              result['city']!.isEmpty &&
              result['district']!.isEmpty)
          ? null
          : result;
    } catch (_) {
      return null;
    }
  }

  /// 用覆盖值替换 IP 快照里的行政区名。坐标与天气仍用 IP 定位的近似值——
  /// 覆盖场景通常是「同城修区县」或「跨城订正」，坐标近似即可，天气再让
  /// 智能体另开 env_snapshot 验证。
  static Map<String, dynamic> _applyOverride(
      Map<String, dynamic> snap, Map<String, String>? override) {
    if (override == null) return snap;
    return {
      ...snap,
      'province': override['province']!.isNotEmpty
          ? override['province']
          : snap['province'],
      'city': override['city']!.isNotEmpty
          ? override['city']
          : snap['city'],
      'district': override['district']!.isNotEmpty
          ? override['district']
          : snap['district'],
      'locationOverridden': true,
    };
  }

  static Future<Map<String, dynamic>?> _fetch() async {
    Map<String, dynamic>? ipInfo;
    try {
      // ① 腾讯位置服务 IP 定位 → 省/市/区 + 经纬度（不传 ip 参数=用出口 IP）
      final res = await HttpUtil().get(
        'https://apis.map.qq.com/ws/location/v1/ip',
        parameters: {'key': DefaultConfig.tencentIpKey},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['status'] != 0) return _fallbackByIpApi();
      final result = data['result'] as Map<String, dynamic>;
      final adInfo = result['ad_info'] as Map<String, dynamic>;
      final location = result['location'] as Map<String, dynamic>;
      ipInfo = {
        'province': adInfo['province']?.toString() ?? '',
        'city': adInfo['city']?.toString() ?? '',
        'district': adInfo['district']?.toString() ?? '',
        'lat': double.tryParse(location['lat'].toString()) ?? 0,
        'lng': double.tryParse(location['lng'].toString()) ?? 0,
      };
    } catch (_) {
      return _fallbackByIpApi();
    }

    // ② 和风实时天气（用 IP 定位的经纬度）
    final weather = await _fetchWeather(
        (ipInfo['lat'] as double), (ipInfo['lng'] as double));
    return _applyOverride({
      ...ipInfo,
      'weather': weather?['text'] ?? '',
      'temp': weather?['temp'] ?? '',
      'feelsLike': weather?['feelsLike'] ?? '',
      'windDir': weather?['windDir'] ?? '',
    }, _override);
  }

  /// 和风专属 API Host（PrefUtil 配置；为空回落旧公共域名，剥协议与尾斜杠）。
  static String get _qweatherHost {
    final h = (PrefUtil.getValue<String>('qweatherHost') ?? '').trim();
    if (h.isEmpty) return 'devapi.qweather.com';
    return h.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/$'), '');
  }

  /// 和风 key：优先 PrefUtil（实验室可改），回落构建注入。
  static String get _qweatherKey {
    final k = PrefUtil.getValue<String>('qweatherKey');
    if (k != null && k.isNotEmpty) return k;
    return DefaultConfig.qweatherKey;
  }

  /// 和风实时天气（v7/weather/now），失败返回 null。
  /// Host 优先取 PrefUtil 配置的专属 API Host，回落旧公共域名；
  /// key 优先取 PrefUtil（用户在实验室可改），回落构建注入。
  static Future<Map<String, String>?> _fetchWeather(
      double lat, double lng) async {
    try {
      final res = await HttpUtil().get(
        'https://$_qweatherHost/v7/weather/now',
        parameters: {
          'location': '${lng.toStringAsFixed(2)},${lat.toStringAsFixed(2)}',
          'key': _qweatherKey,
          'lang': 'zh',
        },
      );
      final weather = await compute(
          WeatherResponse.fromJson, res.data as Map<String, dynamic>);
      final now = weather.now;
      if (now == null) return null;
      return {
        'text': now.text ?? '',
        'temp': now.temp ?? '',
        'feelsLike': now.feelsLike ?? '',
        'windDir': now.windDir ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  /// 兜底：免 key 的 ip-api.com 拿城市 + 天气（腾讯 key 失效/未开通/网络异常时）
  ///
  /// http 明文已在 AndroidManifest 全局放行；免费版 45 次/分钟，仅兜底用。
  /// 返回 province=regionName、city=city（直辖市时 city 实为区级，拼接逻辑
  /// 自动处理）、district 留空，再加和风天气。
  static Future<Map<String, dynamic>?> _fallbackByIpApi() async {
    try {
      final res = await HttpUtil().get(
        'http://ip-api.com/json/',
        parameters: {'lang': 'zh-CN'},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['status'] != 'success') return null;
      final lat = double.tryParse(data['lat'].toString()) ?? 0;
      final lng = double.tryParse(data['lon'].toString()) ?? 0;
      final weather = await _fetchWeather(lat, lng);
      return _applyOverride({
        'province': data['regionName']?.toString() ?? '',
        'city': data['city']?.toString() ?? '',
        'district': '',
        'lat': lat,
        'lng': lng,
        'weather': weather?['text'] ?? '',
        'temp': weather?['temp'] ?? '',
        'feelsLike': weather?['feelsLike'] ?? '',
        'windDir': weather?['windDir'] ?? '',
      }, _override);
    } catch (_) {
      return null;
    }
  }
}
