import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/router/app_router.dart';
import '../data/auth_repository.dart';
import '../domain/user.dart';

/// Provides AuthRepository with Dio instance.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});

// Sentinel object used to distinguish "clear user" from "keep user" in copyWith.
const _keepUser = Object();

/// Auth state: holds current user (null = not logged in).
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  /// Use [clearUser: true] to explicitly set user to null.
  AuthState copyWith({
    Object? user = _keepUser,
    bool? isLoading,
    String? error,
  }) => AuthState(
    user: identical(user, _keepUser) ? this.user : user as User?,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );

  bool get isAuthenticated => user != null;
}

/// AuthNotifier — manages authentication state + connects to GoRouter.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    ref.listen<AuthStatus>(authStateProvider, (previous, next) {
      if (next == AuthStatus.unauthenticated) {
        state = const AuthState();
      }
    });
    // Schedule restore AFTER build() returns — avoids calling ref during build.
    Future.microtask(_restoreSession);
    return const AuthState(isLoading: true);
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Cold start: try restoring user from secure storage.
  Future<void> _restoreSession() async {
    try {
      final user = await _repo.restoreUser();
      if (user != null) {
        state = AuthState(user: user);
        ref.read(authStateProvider.notifier).setAuthenticated();
      } else {
        state = const AuthState();
        ref.read(authStateProvider.notifier).setUnauthenticated();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthNotifier] restoreSession failed: $e');
      state = const AuthState();
      ref.read(authStateProvider.notifier).setUnauthenticated();
    }
  }

  /// Login with email + password.
  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _repo.login(email: email, password: password);
      state = AuthState(user: result.user);
      ref.read(authStateProvider.notifier).setAuthenticated();
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e));
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'authErrorGeneric');
      return false;
    }
  }

  /// Register then auto-login (single loading phase — no double-spinner).
  Future<bool> register({
    required String email,
    required String password,
    String? name,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _repo.register(email: email, password: password, name: name);
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e));
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'authErrorRegisterGeneric',
      );
      return false;
    }

    // Auto-login after successful registration (reuse login logic, stay loading)
    try {
      final result = await _repo.login(email: email, password: password);
      state = AuthState(user: result.user);
      ref.read(authStateProvider.notifier).setAuthenticated();
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e));
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'authErrorLoginAfterRegister',
      );
      return false;
    }
  }

  /// Logout — clear tokens locally + revoke on server.
  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState();
    ref.read(authStateProvider.notifier).setUnauthenticated();
  }

  /// Extract user-facing error message from DioException.
  String _extractError(DioException e) {
    final rawMessage = [
      e.message,
      e.error?.toString(),
      if (e.response?.data is Map && (e.response?.data as Map)['error'] is Map)
        ((e.response?.data as Map)['error'] as Map)['message']?.toString(),
    ].whereType<String>().join(' ').toLowerCase();

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'authErrorTimeout';
      case DioExceptionType.connectionError:
        return 'authErrorNoConnection';
      default:
        break;
    }

    if (rawMessage.contains('socketexception') ||
        rawMessage.contains('connection closed') ||
        rawMessage.contains('failed host lookup') ||
        rawMessage.contains('connection refused') ||
        rawMessage.contains('no route to host')) {
      return 'authErrorNoConnection';
    }

    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final msg = (data['error'] as Map)['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    switch (e.response?.statusCode) {
      case 400:
        return 'authErrorInvalidData';
      case 401:
        return 'authErrorWrongCredentials';
      case 409:
        return 'authErrorEmailExists';
      case 429:
        return 'authErrorTooManyRequests';
      case 500:
      case 503:
        return 'authErrorServerError';
      default:
        return 'authErrorUnknown|${e.response?.statusCode ?? 'unknown'}';
    }
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
