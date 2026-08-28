import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/session/current_user_store.dart';
import '../../create_plan/data/plan_repository.dart';
import '../../create_plan/domain/plan.dart';
import '../../settings/data/settings_repository.dart';
import 'plan_cache.dart';

/// State for all active plans
class PlansState {
  final List<Plan> plans;
  final String? error;
  final bool isFromCache;
  final DateTime loadedAt;

  PlansState({
    this.plans = const [],
    this.error,
    this.isFromCache = false,
    DateTime? loadedAt,
  }) : loadedAt = loadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasPlans => plans.isNotEmpty;

  PlansState copyWith({
    List<Plan>? plans,
    String? error,
    bool? isFromCache,
    DateTime? loadedAt,
  }) {
    return PlansState(
      plans: plans ?? this.plans,
      error: error,
      isFromCache: isFromCache ?? this.isFromCache,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }
}

class PlanNotifier extends AsyncNotifier<PlansState> {
  DateTime _lastEnsureSyncedAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<PlansState> build() async {
    return _loadPlans();
  }

  Future<void> _applyNotificationRules(List<Plan> plans) async {
    final notificationService = ref.read(notificationServiceProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final remindersEnabled = await settingsRepo.getRemindersEnabled();

    if (!remindersEnabled) {
      await notificationService.cancelAllNotifications();
      return;
    }

    await notificationService.rescheduleAllPlans(
      plans,
      mode: NotificationSyncMode.passive,
      reason: 'plan_notifier_apply_notification_rules',
    );
  }

  Future<PlansState> _loadPlans({bool forceRemote = false}) async {
    final userStore = ref.read(currentUserStoreProvider);
    final userId = await userStore.getCurrentUserId();

    if (userId == null || userId.isEmpty) {
      await _applyNotificationRules(const []);
      return PlansState(plans: []);
    }

    final cache = ref.read(planCacheProvider);
    final cachedPlans = await cache.load(userId: userId, activeOnly: true);

    if (!forceRemote && cachedPlans.isNotEmpty) {
      Future.microtask(() async {
        final refreshed = await _refreshFromServer(
          userId,
          fallbackPlans: cachedPlans,
        );
        if (!ref.mounted) {
          return;
        }
        state = AsyncValue.data(refreshed);
      });
      await _applyNotificationRules(cachedPlans);
      return PlansState(
        plans: cachedPlans,
        isFromCache: true,
        loadedAt: DateTime.now(),
      );
    }

    return _refreshFromServer(userId, fallbackPlans: cachedPlans);
  }

  Future<PlansState> _refreshFromServer(
    String userId, {
    List<Plan> fallbackPlans = const [],
  }) async {
    try {
      final repo = ref.read(planRepositoryProvider);
      final plans = await repo.getPlans(activeOnly: true);
      final cache = ref.read(planCacheProvider);
      await cache.save(userId: userId, activeOnly: true, plans: plans);

      await _applyNotificationRules(plans);
      return PlansState(
        plans: plans,
        isFromCache: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (fallbackPlans.isNotEmpty) {
        await _applyNotificationRules(fallbackPlans);
        return PlansState(
          plans: fallbackPlans,
          error: e.toString(),
          isFromCache: true,
          loadedAt: DateTime.now(),
        );
      }

      return PlansState(error: e.toString(), loadedAt: DateTime.now());
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadPlans(forceRemote: true));
  }

  Future<void> syncInBackground() async {
    final next = await _loadPlans(forceRemote: true);
    state = AsyncValue.data(next);
  }

  Future<void> ensureNotificationsSynced({
    bool force = false,
    String reason = 'plan_notifier_ensure',
  }) async {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastEnsureSyncedAt) < const Duration(seconds: 15)) {
      return;
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final remindersEnabled = await settingsRepo.getRemindersEnabled();
    final notificationService = ref.read(notificationServiceProvider);

    if (!remindersEnabled) {
      await notificationService.cancelAllNotifications();
      _lastEnsureSyncedAt = now;
      return;
    }

    final cachedPlansInState = state.asData?.value.plans;
    if (cachedPlansInState != null && cachedPlansInState.isNotEmpty) {
      await notificationService.rescheduleAllPlans(
        cachedPlansInState,
        mode: force ? NotificationSyncMode.force : NotificationSyncMode.passive,
        reason: reason,
      );
      _lastEnsureSyncedAt = now;
      return;
    }

    final userStore = ref.read(currentUserStoreProvider);
    final userId = await userStore.getCurrentUserId();
    if (userId != null && userId.isNotEmpty) {
      final cache = ref.read(planCacheProvider);
      final cachedPlans = await cache.load(userId: userId, activeOnly: true);
      if (cachedPlans.isNotEmpty) {
        await notificationService.rescheduleAllPlans(
          cachedPlans,
          mode: force
              ? NotificationSyncMode.force
              : NotificationSyncMode.passive,
          reason: '${reason}_from_cache',
        );
        _lastEnsureSyncedAt = now;
        return;
      }
    }

    try {
      final repo = ref.read(planRepositoryProvider);
      final plans = await repo.getPlans(activeOnly: true);
      if (userId != null && userId.isNotEmpty) {
        final cache = ref.read(planCacheProvider);
        await cache.save(userId: userId, activeOnly: true, plans: plans);
      }
      await notificationService.rescheduleAllPlans(
        plans,
        mode: force ? NotificationSyncMode.force : NotificationSyncMode.passive,
        reason: '${reason}_remote',
      );
      _lastEnsureSyncedAt = now;
    } catch (_) {
      // Keep existing OS-scheduled alarms when network/auth is unavailable.
      // This prevents accidental cancellation caused by transient empty states.
      return;
    }
  }

  Future<void> clearForCurrentUser() async {
    final userStore = ref.read(currentUserStoreProvider);
    final userId = await userStore.getCurrentUserId();
    if (userId != null && userId.isNotEmpty) {
      final cache = ref.read(planCacheProvider);
      await cache.clearForUser(userId);
    }
    _lastEnsureSyncedAt = DateTime.fromMillisecondsSinceEpoch(0);
    state = AsyncValue.data(PlansState(plans: []));
  }

  void resetInMemory() {
    _lastEnsureSyncedAt = DateTime.fromMillisecondsSinceEpoch(0);
    state = AsyncValue.data(PlansState(plans: []));
  }

  Future<void> clearAllCaches() async {
    final cache = ref.read(planCacheProvider);
    await cache.clearAllUsers();
    _lastEnsureSyncedAt = DateTime.fromMillisecondsSinceEpoch(0);
    state = AsyncValue.data(PlansState(plans: []));
  }
}

final planNotifierProvider = AsyncNotifierProvider<PlanNotifier, PlansState>(
  PlanNotifier.new,
);
