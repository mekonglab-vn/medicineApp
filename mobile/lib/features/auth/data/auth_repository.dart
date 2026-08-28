import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants.dart';
import '../domain/user.dart';

/// Auth repository — handles register, login, refresh, logout with Node.js API.
class AuthRepository {
  final Dio _dio;
  static const _storage = FlutterSecureStorage();
  static const _clearSessionOnBoot = bool.fromEnvironment(
    'QA_RESET_SESSION_ON_BOOT',
  );

  AuthRepository(this._dio);

  /// Register → returns User (does NOT auto-login).
  Future<User> register({
    required String email,
    required String password,
    String? name,
  }) async {
    final response = await _dio.post(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        if (name != null && name.isNotEmpty) 'name': name,
      },
    );

    return User.fromJson(response.data['data']['user'] as Map<String, dynamic>);
  }

  /// Login → saves tokens + user → returns User.
  Future<({User user, String accessToken, String refreshToken})> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );

    final data = response.data['data'] as Map<String, dynamic>;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    final accessToken = data['accessToken'] as String;
    final refreshToken = data['refreshToken'] as String;

    // Save tokens + user to secure storage (sequentially to avoid partial writes)
    await _storage.write(key: AppConstants.accessTokenKey, value: accessToken);
    await _storage.write(
      key: AppConstants.refreshTokenKey,
      value: refreshToken,
    );
    await _storage.write(
      key: AppConstants.userKey,
      value: jsonEncode(user.toJson()),
    );

    return (user: user, accessToken: accessToken, refreshToken: refreshToken);
  }

  /// Try restoring user from secure storage (cold start).
  /// Returns null if tokens are missing.
  Future<User?> restoreUser() async {
    if (_clearSessionOnBoot) {
      await _clearAll();
      return null;
    }

    final userData = await _storage.read(key: AppConstants.userKey);
    final accessToken = await _storage.read(key: AppConstants.accessTokenKey);

    if (userData == null || accessToken == null) return null;

    try {
      return User.fromJson(jsonDecode(userData) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt storage — clear it
      await _clearAll();
      return null;
    }
  }

  /// Logout — clear all tokens locally, then revoke on server.
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout-all');
    } catch (_) {
      // Server call may fail if token already expired — that's OK
    } finally {
      await _clearAll();
    }
  }

  Future<void> _clearAll() async {
    await _storage.delete(key: AppConstants.accessTokenKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.userKey);
  }
}
