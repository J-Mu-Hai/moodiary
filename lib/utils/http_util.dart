import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:moodiary/utils/log_util.dart';

import 'notice_util.dart';

class HttpUtil {
  Dio? _dio;

  /// 静默模式：后台感知（大脑组装上下文、天气轮询等）的网络失败
  /// 不弹「Network Error」toast，避免一次大脑决策刷出一串提示。
  /// 用 [withQuiet] 包裹，使用完自动复位。
  static bool quiet = false;

  final bool _enableLogging = kDebugMode;

  /// 在 [action] 执行期间开启静默模式，结束（含异常）后复位。
  static Future<T> withQuiet<T>(Future<T> Function() action) async {
    final prev = quiet;
    quiet = true;
    try {
      return await action();
    } finally {
      quiet = prev;
    }
  }

  Dio get dio {
    if (_dio == null) {
      _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 12)));
      _dio?.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) {
            if (error.type != DioExceptionType.cancel && !quiet) {
              NoticeUtil.showToast('Network Error ${error.error}');
            }
            handler.next(error);
          },
          onRequest: (options, handler) {
            if (_enableLogging) {
              LogUtil.printInfo('Request: ${options.method} ${options.path}');
            }
            handler.next(options);
          },
          onResponse: (response, handler) {
            if (_enableLogging) {
              LogUtil.printInfo('Response ${response.statusCode}');
            }
            handler.next(response);
          },
        ),
      );
    }
    return _dio!;
  }

  HttpUtil._();

  static final HttpUtil _instance = HttpUtil._();

  factory HttpUtil() => _instance;

  Future<Response<T>> _request<T>(
    String path, {
    required String method,
    Map<String, dynamic>? parameters,
    dynamic data,
    ResponseType? type,
    Map<String, dynamic>? header,
    Options? option,
  }) async {
    final options = (option ?? Options()).copyWith(
      method: method,
      headers: header,
      responseType: type,
    );

    return await dio.request<T>(
      path,
      queryParameters: parameters,
      data: data,
      options: options,
    );
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? parameters,
    ResponseType? type,
  }) {
    return _request(path, method: 'GET', parameters: parameters, type: type);
  }

  Future<Response<T>> post<T>(
    String path, {
    Map<String, dynamic>? header,
    data,
    Options? option,
  }) {
    return _request(
      path,
      method: 'POST',
      header: header,
      data: data,
      option: option,
    );
  }

  Future<Stream<String>?> postStream(
    String path, {
    Map<String, dynamic>? header,
    Object? data,
    Duration? receiveTimeout,
  }) async {
    final Response<ResponseBody> response = await dio.post(
      path,
      options: Options(
        responseType: ResponseType.stream,
        headers: header,
        // 允许调用方按场景覆盖读取超时（SSE 长连接需要足够的时间窗口）。
        // 连接超时是实例级配置（BaseOptions，见 dio 初始化，12s）。
        receiveTimeout: receiveTimeout,
      ),
      data: data,
    );

    final StreamTransformer<Uint8List, List<int>> transformer =
        StreamTransformer.fromHandlers(
          handleData: (data, sink) {
            sink.add(List<int>.from(data));
          },
        );
    return response.data?.stream
        .transform(transformer)
        .transform(const Utf8Decoder())
        .transform(const LineSplitter());
  }

  Future<Response<T>> upload<T>(
    String path, {
    required FormData data,
    Map<String, dynamic>? headers,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    return await dio.post<T>(
      path,
      data: data,
      options: Options(headers: headers),
      onSendProgress: onSendProgress,
    );
  }
}
