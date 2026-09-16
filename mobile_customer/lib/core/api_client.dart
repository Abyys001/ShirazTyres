import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'config.dart';
import 'token_store.dart';

/// Thin Dio wrapper: attaches the customer access token, and on a 401 refreshes
/// once and replays the request. Only a refresh the server actually refuses
/// ends the session — an unreachable API leaves it exactly where it was.
class ApiClient {
  ApiClient(this._tokens, {Dio? dio, this.onAuthLost}) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = AppConfig.apiBaseUrl
      ..connectTimeout = AppConfig.requestTimeout
      ..receiveTimeout = AppConfig.requestTimeout
      ..headers['Accept'] = 'application/json';
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(onRequest: _attachToken, onError: _refreshAndReplay),
    );
  }

  final Dio _dio;
  final TokenStore _tokens;
  final void Function()? onAuthLost;

  static const _retriedFlag = 'st_retried';

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => _dio.post<dynamic>(path, data: body));

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _dio.patch<dynamic>(path, data: body));

  Future<dynamic> delete(String path, {Object? body}) =>
      _send(() => _dio.delete<dynamic>(path, data: body));

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final response = await call();
      return response.data;
    } on DioException catch (error) {
      throw _translate(error);
    }
  }

  Future<void> _attachToken(RequestOptions options, RequestInterceptorHandler handler) async {
    final access = await _tokens.readAccess();
    if (access != null && access.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $access';
    }
    handler.next(options);
  }

  Future<void> _refreshAndReplay(DioException error, ErrorInterceptorHandler handler) async {
    final options = error.requestOptions;
    final retryable = error.response?.statusCode == 401 &&
        options.extra[_retriedFlag] != true &&
        !options.path.contains('/auth/');
    if (!retryable) {
      return handler.next(error);
    }

    switch (await _refreshTokens()) {
      case _Refresh.renewed:
        break;
      case _Refresh.unreachable:
        // Walking into a lift is not a revoked session. The tokens stay put, and
        // the failure is reported as what it was — we could not reach the token
        // endpoint — rather than as the 401 that started it, so nothing
        // upstream reads it as "you are signed out".
        return handler.next(
          DioException.connectionError(
            requestOptions: options,
            reason: 'Could not reach ShirazTyres to renew this session.',
          ),
        );
      case _Refresh.rejected:
        await _tokens.clear();
        onAuthLost?.call();
        return handler.next(error);
    }

    options.extra[_retriedFlag] = true;
    options.headers['Authorization'] = 'Bearer ${await _tokens.readAccess()}';
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (replayError) {
      handler.next(replayError);
    }
  }

  /// Three outcomes rather than a boolean: "could not ask" and "was told no"
  /// have opposite consequences for a session that is meant to last as long as
  /// the app is installed.
  Future<_Refresh> _refreshTokens() async {
    final refresh = await _tokens.readRefresh();
    if (refresh == null || refresh.isEmpty) {
      return _Refresh.rejected;
    }
    // A bare client: the interceptors above must not run against the refresh call.
    final bare = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.requestTimeout,
        receiveTimeout: AppConfig.requestTimeout,
      ),
    );
    try {
      final response = await bare.post<Map<String, dynamic>>(
        '/auth/customer/refresh',
        data: <String, String>{'refresh': refresh},
      );
      final data = response.data;
      if (data == null || data['access'] is! String) {
        return _Refresh.unreachable;
      }
      await _tokens.save(
        access: data['access'] as String,
        refresh: data['refresh'] is String ? data['refresh'] as String : refresh,
      );
      return _Refresh.renewed;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final refused = status == 400 || status == 401 || status == 403;
      return refused ? _Refresh.rejected : _Refresh.unreachable;
    }
  }

  ApiException _translate(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;

    if (data is Map) {
      final fieldErrors = <String, List<String>>{};
      final raw = data['errors'];
      if (raw is Map) {
        raw.forEach((key, value) {
          fieldErrors['$key'] =
              value is List ? value.map((item) => '$item').toList() : <String>['$value'];
        });
      }
      final detail = data['detail'];
      final message = detail is String && detail.isNotEmpty
          ? detail
          : fieldErrors.values.firstWhere(
              (messages) => messages.isNotEmpty,
              orElse: () => <String>[_fallback(error, status)],
            ).first;
      return ApiException(message, statusCode: status, fieldErrors: fieldErrors);
    }

    return ApiException(_fallback(error, status), statusCode: status);
  }

  String _fallback(DioException error, int? status) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return 'Cannot reach ShirazTyres. Check your signal and try again.';
      default:
        if (status == 429) {
          return 'Too many attempts. Wait a minute and try again.';
        }
        if (status != null && status >= 500) {
          return 'ShirazTyres is having trouble. Call us on ${AppConfig.officePhone}.';
        }
        return 'Something went wrong. Please try again.';
    }
  }
}

/// The result of asking the API for a new pair of tokens.
enum _Refresh { renewed, unreachable, rejected }
