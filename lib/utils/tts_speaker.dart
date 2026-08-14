import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:moodiary/common/values/default_config.dart';
import 'package:moodiary/utils/file_util.dart';
import 'package:moodiary/utils/http_util.dart';
import 'package:moodiary/utils/log_util.dart';

/// 豆包语音合成（V3 大模型音色）+ audioplayers 播放。
///
/// 接口：POST https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse
/// 鉴权：新版 API Key 走 header `X-Api-Key` + `X-Api-Resource-Id: seed-tts-2.0`
///       （不是旧版 openspeech 的 `Authorization: Bearer;<token>`）
/// 响应：SSE 流，`event: 352` 行的 data 为 base64 mp3 分片，`event: 152`(code
///       20000000) 表示合成结束。多分片 base64 需拼接后整体解码。
class TtsSpeaker {
  /// 大模型音色（seed-tts-2.0 资源配套；经典音色如 zh_female_shuangkuaisisi 与
  /// 该资源不匹配会报 55000000）。可在此调整为其他大模型音色。
  static const String _speaker = 'zh_female_vv_uranus_bigtts';
  static const String _resourceId = 'seed-tts-2.0';

  static final AudioPlayer _player = AudioPlayer();

  /// 最近一次失败原因（供 UI 展示具体错误，如 toast）
  static String lastError = '';

  /// 合成并播放指定文本。成功返回 true，失败返回 false（不抛出）。
  static Future<bool> speak(String text) async {
    lastError = '';
    if (DefaultConfig.doubaoTtsKey.isEmpty || text.trim().isEmpty) {
      lastError = '豆包 key 为空';
      return false;
    }

    final body = {
      'user': {'uid': 'moodiary'},
      'req_params': {
        'text': text,
        'speaker': _speaker,
        'sample_rate': 24000,
        'audio_params': {'format': 'mp3'},
      },
    };

    try {
      final lines = await HttpUtil().postStream(
        'https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse',
        header: {
          'Content-Type': 'application/json',
          'X-Api-Key': DefaultConfig.doubaoTtsKey,
          'X-Api-Resource-Id': _resourceId,
          'X-Api-Request-Id': _genReqId(),
        },
        data: body,
      );
      if (lines == null) {
        lastError = 'TTS 连接失败';
        return false;
      }

      // 逐行解析 SSE：收集所有 code==0 的音频分片，遇到结束事件退出
      final chunks = <String>[];
      await for (final line in lines) {
        final t = line.trim();
        if (!t.startsWith('data:')) continue;
        final jsonStr = t.substring('data:'.length).trim();
        if (jsonStr.isEmpty) continue;
        final Map<String, dynamic> evt;
        try {
          evt = jsonDecode(jsonStr) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final code = evt['code'];
        if (code == 0) {
          final b64 = evt['data']?.toString();
          if (b64 != null && b64.isNotEmpty) chunks.add(b64);
        } else if (code == 20000000) {
          break; // 合成结束
        } else {
          lastError = '合成失败 code=$code msg=${evt['message']}';
          LogUtil.printInfo('[TTS] 合成失败 code=$code msg=${evt['message']}');
          return false;
        }
      }

      if (chunks.isEmpty) {
        lastError = '未收到音频数据';
        LogUtil.printInfo('[TTS] 未收到音频数据');
        return false;
      }

      final audioBytes = base64Decode(chunks.join());
      final tmpPath = FileUtil.getCachePath('tts_${_genReqId()}.mp3');
      await File(tmpPath).writeAsBytes(audioBytes);
      await _player.play(DeviceFileSource(tmpPath));
      return true;
    } catch (e) {
      lastError = '错误: $e';
      LogUtil.printInfo('[TTS] 错误: $e');
      return false;
    }
  }

  /// 生成 UUID 风格的唯一请求 ID（reqid 每次合成必须唯一）
  static String _genReqId() {
    final rnd = Random();
    const chars = '0123456789abcdef';
    final h = List.generate(32, (_) => chars[rnd.nextInt(16)]).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '4${h.substring(13, 16)}-'
        '${'89ab'[rnd.nextInt(4)]}${h.substring(17, 20)}-'
        '${h.substring(20)}';
  }
}
