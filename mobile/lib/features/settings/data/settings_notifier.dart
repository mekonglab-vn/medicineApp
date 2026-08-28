import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../create_plan/data/plan_repository.dart';
import '../../home/data/plan_notifier.dart';
import 'settings_repository.dart';

class SettingsState {
  const SettingsState({this.remindersEnabled = true, this.isLoading = false});

  final bool remindersEnabled;
  final bool isLoading;

  SettingsState copyWith({bool? remindersEnabled, bool? isLoading}) {
    return SettingsState(
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async {
    final repo = ref.read(settingsRepositoryProvider);
    final enabled = await repo.getRemindersEnabled();
    return SettingsState(remindersEnabled: enabled);
  }

  Future<bool> setRemindersEnabled(bool enabled) async {
    state = AsyncValue.data(state.value!.copyWith(isLoading: true));
    try {
      final notificationService = ref.read(notificationServiceProvider);

      if (enabled) {
        final hasPerm = await notificationService.hasPermissions();
        if (!hasPerm) {
          await notificationService.requestPermissions();
          final hasPermAfter = await notificationService.hasPermissions();
          if (!hasPermAfter) {
            state = AsyncValue.data(state.value!.copyWith(isLoading: false));
            return false;
          }
        }
      }

      final repo = ref.read(settingsRepositoryProvider);
      await repo.setRemindersEnabled(enabled);

      if (!enabled) {
        await notificationService.cancelAllNotifications();
      } else {
        notificationService.markNotificationsDirty('reminders_enabled');
        final plansAsync = ref.read(planNotifierProvider);
        final cachedPlans = plansAsync.asData?.value.plans;
        if (cachedPlans != null) {
          await notificationService.rescheduleAllPlans(
            cachedPlans,
            mode: NotificationSyncMode.force,
            reason: 'settings_enable',
          );
        } else {
          final planRepository = ref.read(planRepositoryProvider);
          final plans = await planRepository.getPlans(activeOnly: true);
          await notificationService.rescheduleAllPlans(
            plans,
            mode: NotificationSyncMode.force,
            reason: 'settings_enable_fetch',
          );
        }
      }

      state = AsyncValue.data(
        SettingsState(remindersEnabled: enabled, isLoading: false),
      );
      return true;
    } catch (e) {
      state = AsyncValue.data(state.value!.copyWith(isLoading: false));
      return false;
    }
  }
}

final settingsNotifierProvider =
    AsyncNotifierProvider<SettingsNotifier, SettingsState>(
      SettingsNotifier.new,
    );
