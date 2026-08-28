import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:medicine_app/l10n/app_localizations.dart';

import '../../../core/theme/app_theme.dart';
import '../data/auth_notifier.dart';

String _translateAuthError(BuildContext context, String? error) {
  if (error == null) return '';
  final l10n = AppLocalizations.of(context);
  switch (error) {
    case 'authErrorTimeout':
      return l10n.authErrorTimeout;
    case 'authErrorNoConnection':
      return l10n.authErrorNoConnection;
    case 'authErrorInvalidData':
      return l10n.authErrorInvalidData;
    case 'authErrorWrongCredentials':
      return l10n.authErrorWrongCredentials;
    case 'authErrorEmailExists':
      return l10n.authErrorEmailExists;
    case 'authErrorTooManyRequests':
      return l10n.authErrorTooManyRequests;
    case 'authErrorServerError':
      return l10n.authErrorServerError;
    case 'authErrorGeneric':
      return l10n.commonErrorGeneric;
    case 'authErrorRegisterGeneric':
      return l10n.authErrorRegisterGeneric;
    case 'authErrorLoginAfterRegister':
      return l10n.authErrorLoginAfterRegister;
    default:
      if (error.startsWith('authErrorUnknown|')) {
        return l10n.authErrorUnknown(error.split('|').last);
      }
      return error; // For server-provided error messages
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authErrorEmptyEmailPassword)),
      );
      return;
    }

    final success = await ref
        .read(authNotifierProvider.notifier)
        .login(email: email, password: password);

    if (!success && mounted) {
      final error = ref.read(authNotifierProvider).error;
      final msg = _translateAuthError(context, error);
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : l10n.authErrorLoginFailed),
          backgroundColor: AppColors.error,
        ),
      );
    }
    // If success → GoRouter auto-redirects to /home
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo & Title
              Icon(
                Icons.medical_services_rounded,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.authLoginTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.authLoginSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 48),

              // Email
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !authState.isLoading,
                decoration: InputDecoration(
                  hintText: l10n.authEmailHint,
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Password
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                enabled: !authState.isLoading,
                onSubmitted: (_) => _handleLogin(),
                decoration: InputDecoration(
                  hintText: l10n.authPasswordHint,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Login button
              ElevatedButton(
                onPressed: authState.isLoading ? null : _handleLogin,
                child: authState.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.authLoginButton),
              ),
              const SizedBox(height: 16),

              // Register link
              TextButton(
                onPressed: authState.isLoading
                    ? null
                    : () => context.go('/register'),
                child: Text.rich(
                  TextSpan(
                    text: l10n.authNoAccountPrompt,
                    style: const TextStyle(color: AppColors.textSecondary),
                    children: [
                      TextSpan(
                        text: l10n.authRegisterAction,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
