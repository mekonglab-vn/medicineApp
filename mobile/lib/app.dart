import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_notifier.dart';
import 'features/home/data/plan_notifier.dart';
import 'features/home/data/today_schedule_notifier.dart';
import 'l10n/app_localizations.dart';

/// Root app widget with Riverpod + GoRouter + healthcare light theme.
///
/// Localization:
///   - default locale: vi (Vietnamese)
///   - delegates: AppLocalizations + Flutter material/cupertino/widgets
class MedicineApp extends ConsumerWidget {
  const MedicineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authNotifierProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Uống thuốc',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) =>
          _NotificationActionBridge(child: child ?? const SizedBox.shrink()),
      // ── Localization ──────────────────────────────────────────────
      locale: const Locale('vi'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    );
  }
}

class _NotificationActionBridge extends ConsumerStatefulWidget {
  const _NotificationActionBridge({required this.child});

  final Widget child;

  @override
  ConsumerState<_NotificationActionBridge> createState() =>
      _NotificationActionBridgeState();
}

class _NotificationActionBridgeState
    extends ConsumerState<_NotificationActionBridge> {
  final List<NotificationActionEvent> _pendingEvents = [];
  StreamSubscription<NotificationActionEvent>? _subscription;
  bool _isProcessing = false;
  late final AppLifecycleListener _lifecycleListener;
  DateTime? _lastResumeSyncAt;

  static const Duration _resumeSyncDebounce = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    final notificationService = ref.read(notificationServiceProvider);
    _subscription = notificationService.actionEvents.listen(_enqueueEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final event in notificationService.takePendingLaunchEvents()) {
        _enqueueEvent(event);
      }
    });

    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (!mounted) {
          return;
        }
        if (ref.read(authStateProvider) == AuthStatus.authenticated) {
          final now = DateTime.now();
          final last = _lastResumeSyncAt;
          if (last != null && now.difference(last) < _resumeSyncDebounce) {
            return;
          }
          _lastResumeSyncAt = now;
          unawaited(ref.read(planNotifierProvider.notifier).syncInBackground());
          unawaited(
            ref
                .read(planNotifierProvider.notifier)
                .ensureNotificationsSynced(reason: 'app_resume'),
          );
          unawaited(ref.read(todayScheduleNotifierProvider.notifier).refresh());
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  void _enqueueEvent(NotificationActionEvent event) {
    if (!event.isTakenAction) {
      return;
    }
    _pendingEvents.add(event);
    _drainPendingEvents();
  }

  Future<void> _drainPendingEvents() async {
    if (!mounted || _isProcessing) {
      return;
    }
    if (ref.read(authStateProvider) != AuthStatus.authenticated) {
      return;
    }

    _isProcessing = true;
    while (mounted && _pendingEvents.isNotEmpty) {
      final event = _pendingEvents.removeAt(0);
      final result = await ref
          .read(todayScheduleNotifierProvider.notifier)
          .markDoseFromNotification(event);
      if (!mounted) {
        break;
      }

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        continue;
      }

      final (message, backgroundColor) = switch (result) {
        MarkDoseResult.synced => (
          'Đã ghi nhận uống thuốc: ${event.title}',
          AppColors.success,
        ),
        MarkDoseResult.queuedOffline => (
          'Đã lưu tạm offline: ${event.title}',
          AppColors.warning,
        ),
        MarkDoseResult.failed => (
          'Không ghi nhận được liều uống từ thông báo.',
          AppColors.error,
        ),
      };

      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: backgroundColor),
      );
    }
    _isProcessing = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthStatus>(authStateProvider, (_, next) {
      if (next == AuthStatus.authenticated) {
        unawaited(ref.read(planNotifierProvider.notifier).syncInBackground());
        unawaited(ref.read(todayScheduleNotifierProvider.notifier).refresh());
        unawaited(
          ref
              .read(planNotifierProvider.notifier)
              .ensureNotificationsSynced(reason: 'auth_authenticated'),
        );
        _drainPendingEvents();
      }

      if (next == AuthStatus.unauthenticated) {
        _pendingEvents.clear();
        ref.read(planNotifierProvider.notifier).resetInMemory();
        ref.read(todayScheduleNotifierProvider.notifier).resetInMemory();
      }
    });
    return widget.child;
  }
}
