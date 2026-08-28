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
    case 'authErrorTimeout': return l10n.authErrorTimeout;
    case 'authErrorNoConnection': return l10n.authErrorNoConnection;
    case 'authErrorInvalidData': return l10n.authErrorInvalidData;
    case 'authErrorWrongCredentials': return l10n.authErrorWrongCredentials;
    case 'authErrorEmailExists': return l10n.authErrorEmailExists;
    case 'authErrorTooManyRequests': return l10n.authErrorTooManyRequests;
    case 'authErrorServerError': return l10n.authErrorServerError;
    case 'authErrorGeneric': return l10n.commonErrorGeneric;
    case 'authErrorRegisterGeneric': return l10n.authErrorRegisterGeneric;
    case 'authErrorLoginAfterRegister': return l10n.authErrorLoginAfterRegister;
    default:
      if (error.startsWith('authErrorUnknown|')) {
        return l10n.authErrorUnknown(error.split('|').last);
      }
      return error;
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    // Validation
    final l10n = AppLocalizations.of(context);
    if (email.isEmpty || password.isEmpty) {
      _showError(l10n.authErrorEmptyEmailPassword);
      return;
    }
    if (password.length < 8) {
      _showError(l10n.authErrorPasswordLength);
      return;
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      _showError(l10n.authErrorPasswordUppercase);
      return;
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      _showError(l10n.authErrorPasswordNumber);
      return;
    }
    if (password != confirm) {
      _showError(l10n.authErrorPasswordMismatch);
      return;
    }

    final success = await ref
        .read(authNotifierProvider.notifier)
        .register(
          email: email,
          password: password,
          name: name.isNotEmpty ? name : null,
        );

    if (!success && mounted) {
      final error = ref.read(authNotifierProvider).error;
      final msg = _translateAuthError(context, error);
      _showError(msg.isNotEmpty ? msg : AppLocalizations.of(context).authErrorRegisterFailed);
    }
    // If success → auto-login → GoRouter redirects to /home
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.person_add_rounded,
                size: 56,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.authRegisterTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.authRegisterSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 36),

              // Name (optional)
              TextField(
                controller: _nameController,
                enabled: !authState.isLoading,
                decoration: InputDecoration(
                  hintText: l10n.authNameOptionalHint,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

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
                decoration: InputDecoration(
                  hintText: l10n.authPasswordRequirements,
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
              const SizedBox(height: 16),

              // Confirm password
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                enabled: !authState.isLoading,
                onSubmitted: (_) => _handleRegister(),
                decoration: InputDecoration(
                  hintText: l10n.authPasswordConfirmHint,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 24),

              // Register button
              ElevatedButton(
                onPressed: authState.isLoading ? null : _handleRegister,
                child: authState.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.authRegisterButton),
              ),
              const SizedBox(height: 16),

              // Login link
              TextButton(
                onPressed: authState.isLoading
                    ? null
                    : () => context.go('/login'),
                child: Text.rich(
                  TextSpan(
                    text: l10n.authHasAccountPrompt,
                    style: const TextStyle(color: AppColors.textSecondary),
                    children: [
                      TextSpan(
                        text: l10n.authLoginAction,
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
