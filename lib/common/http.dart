import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_storage/get_storage.dart';


/// 重新登录回调类型定义
/// 返回值 true 表示重新登录成功（如刷新 Token 成功），可重试原请求；
/// 返回值 false 表示失败或用户取消，直接返回 401 错误。
typedef OnUnauthorized = Future<bool> Function();

class Http {
  // 单例模式
  static final Http _instance = Http._internal();

  factory Http() => _instance;

  Http._internal();

  late Dio _dio;
  OnUnauthorized? _onUnauthorized;

  // 获取存储实例
  final GetStorage _storage = GetStorage();

  // 用于处理 401 并发请求的锁, 是否正在刷新 token
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;
  // 等待队列: 存储因 token 过期而挂起的请求
  // final List<QueuedRequest> _queuedRequests = [];

  // 不需要权限就能访问的 url
  List<String> _ignoreAuthorizationUrls = [
    '/ums/auth/device/login',
    '/cms/app/1776737067/version/latest'
  ];


  // 初始化配置
  void init({String baseUrl = 'http://127.0.0.1'}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    // 添加拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
      onError: _onError,
    ));
  }

  /// 配置基础 URL、头部、拦截器等（可选）
  void config({
    String? baseUrl,
    Map<String, dynamic>? headers,
    int? connectTimeout,
    int? receiveTimeout,
    int? sendTimeout,
    List<Interceptor>? interceptors,
  }) {
    _dio.options.baseUrl = baseUrl ?? _dio.options.baseUrl;
    _dio.options.headers.addAll(headers ?? {});
    _dio.options.connectTimeout = Duration(seconds: connectTimeout ?? 15);
    _dio.options.receiveTimeout = Duration(seconds: receiveTimeout ?? 15);
    _dio.options.sendTimeout = Duration(seconds: sendTimeout ?? 15);
    if (interceptors != null) {
      _dio.interceptors.addAll(interceptors);
    }
  }

  /// 设置 401 回调
  void setUnauthorizedCallback(OnUnauthorized callback) {
    _onUnauthorized = callback;
  }

  void setIgnoreAuthorizationUrls(List<String> urls) {
    _ignoreAuthorizationUrls = urls;
  }


  /// 请求拦截器
  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // 忽略不需要添加 token 的请求 urls
    if (_ignoreAuthorizationUrls.contains(options.path)) {
      handler.next(options);
      return;
    }

    // 添加 Authorization 请求头
    final token = _storage.read<String>('Authorization');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }


  /// 响应拦截器
  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    // final String? contentType = response.headers.value('content-type');

    // 可统一处理响应数据格式
    // handler.next(response);

    // 传递到下一个拦截器, 如果当前拦截器已经是最后一个，Dio 会将错误抛给调用方（即 Future.catchError 或 try-catch）。
    handler.next(response);
  }


  /// 错误拦截器, status >= 300 抛异常; 网络异常
  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    print('[Http:_onError] type=${error.type}, message=${error.message}');

    switch (error.type) {
      case DioExceptionType.badResponse: // 状态码 >= 300
        _handleBadResponse(error, handler);
        break;
      case DioExceptionType.connectionTimeout: // 连接超时, response = null
      case DioExceptionType.sendTimeout: // 发送数据超时
      case DioExceptionType.receiveTimeout: // 接收数据超时, response = null
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel: // 主动取消
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        _handleNetworkException(error, handler);
        break;
    }

    // 传递到下一个拦截器, 如果当前拦截器已经是最后一个，Dio 会将错误抛给调用方（即 Future.catchError 或 try-catch）。
    // handler.next(error);
  }

  /// 处理网络错误
  void _handleNetworkException(DioException error, ErrorInterceptorHandler handler) {
    Get.toNamed('/network_error');
  }


  /// 处理错误响应
  void _handleBadResponse(DioException error, ErrorInterceptorHandler handler) {
    Response? response = error.response;
    if (response == null) {
      throw Exception("未知错误");
    }

    int? statusCode = response.statusCode;
    String? statusMessage = response.statusMessage;
    final data = response.data;

    // 错误提示
    if (statusCode == 400) {
      Get.defaultDialog(title: "提示", middleText: data['message']);
    }
    // 未登录, token无效, token过期
    if (statusCode == 401) {
      _handleUnauthorized2(error, handler);
    }
    // 没有访问权限
    if (response.statusCode == 403) {
      throw Exception(data['message']);
    }
    // 请求不存在
    if (response.statusCode == 404) {
      throw Exception(data['message']);
    }
    if (response.statusCode == 500) {
      throw Exception(data['message']);
    }
    if (response.statusCode == 502) {
      Get.toNamed('/502');
      // throw Exception("系统维护中");
    }
  }

  /// 处理 401，返回 true 表示重试请求
  Future<void> _handleUnauthorized2(DioException error, ErrorInterceptorHandler handler) async {
    final shouldRetry = await _retryLogin(error.requestOptions);
    if (shouldRetry) {
      try {
        final opts = error.requestOptions;
        // 重试原请求（注意：此时 token 已刷新）
        final response = await _dio.fetch(opts);
        // 终止链，直接返回成功响应（后续拦截器不再执行）
        return handler.resolve(response);
      } catch (e) {
        return handler.next(e as DioException);
      }
    }
  }

  /// 处理 401，返回 true 表示重试请求
  Future<bool> _retryLogin(RequestOptions options) async {
    if (_onUnauthorized == null) return false;

    // 如果正在刷新，等待刷新完成
    if (_isRefreshing) {
      return _refreshCompleter?.future ?? Future.value(false);
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      final success = await _onUnauthorized!.call();
      _refreshCompleter?.complete(success);
      return success;
    } catch (e) {
      _refreshCompleter?.complete(false);
      return false;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }



  Options _checkOptions(String method, Options? options) {
    options ??= Options();
    options.method = method;
    return options;
  }

  T _parseResponse<T>(Response response, T Function(dynamic json) fromJson) {
    return fromJson(response.data);
  }


  // ---------- 基础请求方法 ----------
  Future<dynamic> request<T>( String method, String path, {
    Map<String, dynamic>? queryParameters,
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress
  }) async {

    final response = await _dio.request(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _checkOptions(method, options),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    return response.data;
  }

  /// status <= 299 返回数据
  /// status >= 300 抛出异常, 走 _onError
  Future<dynamic> get(String path, {Map<String, dynamic>? params}) async {
    final Response<dynamic> response = await _dio.get(path, queryParameters: params);
    return response.data;
  }

  /// status <= 299 返回数据
  /// status >= 300 抛出异常, 走 _onError
  Future<dynamic> post(String path, {dynamic data}) async {
    final Response<dynamic> response = await _dio.post(path, data: data);
    return response.data;
  }

  /// 下载文件
  Future<void> download(
    String url,
    String savePath, {
      Map<String, dynamic>? queryParameters,
      Options? options,
      CancelToken? cancelToken,
      ProgressCallback? onReceiveProgress,
      bool deleteOnError = true,
    }) async {
    final response = await _dio.download(
      url,
      savePath,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
      deleteOnError: deleteOnError,
    );
  }

}