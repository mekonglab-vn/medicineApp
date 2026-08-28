import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants.dart';
import 'network_error_mapper.dart';
import '../router/app_router.dart';

/// Provides a configured Dio instance with auth interceptor.
final dioProvider = Provider<Dio>((ref) {
  const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3001/api',
  );
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: AppConstants.apiTimeout,
      receiveTimeout: AppConstants.apiTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.add(AuthInterceptor(dio, ref));
  dio.interceptors.add(NetworkDiagnosticsInterceptor());
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  return dio;
});

/// Auth interceptor: attaches JWT, auto-refreshes on 401.
class AuthInterceptor extends Interceptor {
  final Dio _dio;
  final Ref _ref;
  static const _storage = FlutterSecureStorage();

  AuthInterceptor(this._dio, this._ref);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth for login/register/refresh
    final noAuthPaths = ['/auth/login', '/auth/register', '/auth/refresh'];
    if (noAuthPaths.any((p) => options.path.endsWith(p))) {
      return handler.next(options);
    }

    final token = await _storage.read(key: AppConstants.accessTokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Skip refresh retry for auth endpoints
    if (err.requestOptions.path.endsWith('/auth/refresh') ||
        err.requestOptions.path.endsWith('/auth/login')) {
      return handler.next(err);
    }

    // Try refreshing token
    try {
      final refreshToken = await _storage.read(
        key: AppConstants.refreshTokenKey,
      );
      if (refreshToken == null) {
        await _clearTokensAndRedirect();
        return handler.next(err);
      }

      final dio = Dio(
        BaseOptions(
          baseUrl: err.requestOptions.baseUrl,
          headers: {'Content-Type': 'application/json'},
        ),
      );

      final response = await dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        await _storage.write(
          key: AppConstants.accessTokenKey,
          value: data['accessToken'],
        );
        await _storage.write(
          key: AppConstants.refreshTokenKey,
          value: data['refreshToken'],
        );

        // Retry original request using the same Dio instance (preserves options/interceptors)
        err.requestOptions.headers['Authorization'] =
            'Bearer ${data['accessToken']}';
        final retryResponse = await _dio.fetch(err.requestOptions);
        return handler.resolve(retryResponse);
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[AuthInterceptor] Token refresh failed: $e\n$stack');
      }
    }

    await _clearTokensAndRedirect();
    handler.next(err);
  }

  Future<void> _clearTokensAndRedirect() async {
    await _storage.delete(key: AppConstants.accessTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.userKey);
    _ref.read(authStateProvider.notifier).setUnauthenticated();
  }
}

class NetworkDiagnosticsInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final issue = classifyNetworkIssue(err);
    err.requestOptions.extra['network_issue_kind'] = issue.name;

    if (kDebugMode) {
      debugPrint(
        '[NetworkDiagnostics] ${err.requestOptions.method} ${err.requestOptions.path} -> ${issue.name}',
      );
    }

    handler.next(err);
  }
}
