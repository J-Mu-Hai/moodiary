import 'package:flutter/foundation.dart';
import 'package:moodiary/common/models/weather.dart';
import 'package:moodiary/common/values/default_config.dart';
import 'package:moodiary/utils/http_util.dart';

/// 环境感知：IP 定位 → 城市 → 和风实时天气。
///
/// 主通道为腾讯位置服务 IP 定位（零权限、城市级），天气用和风按经纬度查询。
/// 腾讯失败时兜底走免 key 的 ip-api.com（http，中文，45 次/分钟）。
/// 返回结构化快照，供智能体函数 `env_snapshot` 与环境播报使用。
class EnvironmentSensor {
  /// 获取环境快照。失败返回 null。
  static Future<Map<String, dynamic>?> getSnapshot() async {
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
    return {
      ...ipInfo,
      'weather': weather?['text'] ?? '',
      'temp': weather?['temp'] ?? '',
      'feelsLike': weather?['feelsLike'] ?? '',
      'windDir': weather?['windDir'] ?? '',
    };
  }

  /// 和风实时天气（devapi /v7/weather/now），失败返回 null
  static Future<Map<String, String>?> _fetchWeather(
      double lat, double lng) async {
    try {
      final res = await HttpUtil().get(
        'https://devapi.qweather.com/v7/weather/now',
        parameters: {
          'location': '${lng.toStringAsFixed(2)},${lat.toStringAsFixed(2)}',
          'key': DefaultConfig.qweatherKey,
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
      return {
        'province': data['regionName']?.toString() ?? '',
        'city': data['city']?.toString() ?? '',
        'district': '',
        'lat': lat,
        'lng': lng,
        'weather': weather?['text'] ?? '',
        'temp': weather?['temp'] ?? '',
        'feelsLike': weather?['feelsLike'] ?? '',
        'windDir': weather?['windDir'] ?? '',
      };
    } catch (_) {
      return null;
    }
  }
}
