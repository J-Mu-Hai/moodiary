import 'dart:math';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:moodiary/common/models/map.dart';
import 'package:moodiary/presentation/pref.dart';

class MapState {
  LatLng? currentLatLng;

  List<DiaryMapItem> diaryMapItemList = [];

  String? tiandituKey = PrefUtil.getValue<String>('tiandituKey');

  /// 瓦片下载专用 Dio（独立实例）。
  ///
  /// 绝不能复用全局单例 [HttpUtil().dio]：CachedTileProvider 构造时会往传入的
  /// Dio 上挂 DioCacheInterceptor，若挂了单例，之后所有经单例发出的 stream
  /// 请求（如豆包 TTS 的 SSE）都会被缓存拦截器拦截并抛
  /// “Response type not supported : ResponseType.stream”。
  final Dio tileDio = Dio();

  String vecUrl =
      'https://t6.tianditu.gov.cn/vec_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=vec&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk={key}';
  String cvaUrl =
      'https://t6.tianditu.gov.cn/cva_w/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=cva&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk={key}';

  int random = Random().nextInt(8);

  MapState();
}
