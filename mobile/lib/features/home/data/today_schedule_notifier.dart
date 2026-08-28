import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/notifications/notification_service.dart';
import '../../create_plan/data/offline_dose_queue.dart';
import '../../create_plan/data/plan_repository.dart';
import '../domain/today_schedule.dart';
import 'today_schedule_cache.dart';

enum MarkDoseResult { synced, queuedOffline, failed }

class TodayScheduleNotifier extends AsyncNotifier<TodaySchedule> {
  @override
  Future<TodaySchedule> build() async {
    return _loadAndRevalidate();
  }

  Future<TodaySchedule> _loadAndRevalidate() async {
    final cache = ref.read(todayScheduleCacheProvider);
    final cached = await cache.load();

    if (cached != null) {
      state = AsyncValue.data(await _applyOfflineQueue(cached.recount()));
    }

    try {
      await flushOfflineQueue();
      final repo = ref.read(planRepositoryProvider);
      final fresh = await _syncExpiredMissedDoses(
        await repo.getTodaySchedule(),
      );
      final merged = await _applyOfflineQueue(fresh.recount());

      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.scheduleDosesFromTodaySummary(merged.doses);

      await cache.save(merged.recount());
      return merged.recount();
    } catch (e, st) {
      if (cached != null) {
        return await _applyOfflineQueue(cached.recount());
      }
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<TodaySchedule> _applyOfflineQueue(TodaySchedule schedule) async {
    final queue = ref.read(offlineDoseQueueProvider);
    final pendingLogs = await queue.getPendingLogs();

    if (pendingLogs.isEmpty) return schedule.recount();

    final logMap = {
      for (final item in pendingLogs) item.occurrenceId: item.status,
    };
    return _replaceStatuses(schedule, logMap);
  }

  Future<TodaySchedule> _syncExpiredMissedDoses(TodaySchedule schedule) async {
    final now = DateTime.now();
    final expired = schedule.doses
        .where((dose) => dose.shouldAutoMiss(now))
        .toList();
    if (expired.isEmpty) {
      return schedule.recount(now);
    }

    final repo = ref.read(planRepositoryProvider);
    final queue = ref.read(offlineDoseQueueProvider);
    final notificationService = ref.read(notificationServiceProvider);
    final updatedStatuses = <String, String>{};

    for (final dose in expired) {
      await notificationService.cancelOccurrenceNotifications(
        dose.occurrenceId,
      );
      try {
        await repo.logDose(
          planId: dose.planId,
          scheduledTime: dose.scheduledTime,
          status: 'missed',
          occurrenceId: dose.occurrenceId,
        );
        updatedStatuses[dose.occurrenceId] = 'missed';
      } catch (e) {
        final issue = classifyNetworkIssue(e);
        if (issue == NetworkIssueKind.noConnection ||
            issue == NetworkIssueKind.timeout ||
            issue == NetworkIssueKind.serviceUnavailable ||
            issue == NetworkIssueKind.serverError) {
          await queue.enqueue(
            PendingDoseLog(
              planId: dose.planId,
              scheduledTime: dose.scheduledTime,
              status: 'missed',
              occurrenceId: dose.occurrenceId,
              queuedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
          updatedStatuses[dose.occurrenceId] = 'missed';
        }
      }
    }

    if (updatedStatuses.isEmpty) {
      return schedule.recount(now);
    }

    return _replaceStatuses(schedule, updatedStatuses);
  }

  Future<int> flushOfflineQueue() async {
    final queue = ref.read(offlineDoseQueueProvider);
    return queue.flush();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await flushOfflineQueue();
      final repo = ref.read(planRepositoryProvider);
      final fresh = await _syncExpiredMissedDoses(
        await repo.getTodaySchedule(),
      );
      final merged = await _applyOfflineQueue(fresh.recount());

      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.scheduleDosesFromTodaySummary(merged.doses);

      final cache = ref.read(todayScheduleCacheProvider);
      await cache.save(merged.recount());

      return merged.recount();
    });
  }

  Future<MarkDoseResult> markDose({
    required TodayDose dose,
    required String status,
  }) async {
    return _commitStatus(
      planId: dose.planId,
      scheduledTime: dose.scheduledTime,
      occurrenceId: dose.occurrenceId,
      status: status,
    );
  }

  Future<MarkDoseResult> markDoseFromNotification(
    NotificationActionEvent event,
  ) async {
    return _commitStatus(
      planId: event.planId,
      scheduledTime: event.scheduledTime,
      occurrenceId: event.occurrenceId,
      status: 'taken',
    );
  }

  Future<MarkDoseResult> _commitStatus({
    required String planId,
    required String scheduledTime,
    required String occurrenceId,
    required String status,
  }) async {
    final queue = ref.read(offlineDoseQueueProvider);
    final notificationService = ref.read(notificationServiceProvider);

    await notificationService.cancelOccurrenceNotifications(occurrenceId);

    try {
      final repo = ref.read(planRepositoryProvider);
      await repo.logDose(
        planId: planId,
        scheduledTime: scheduledTime,
        status: status,
        occurrenceId: occurrenceId,
      );
      await refresh();
      return MarkDoseResult.synced;
    } catch (e) {
      final issue = classifyNetworkIssue(e);
      if (issue != NetworkIssueKind.noConnection &&
          issue != NetworkIssueKind.timeout &&
          issue != NetworkIssueKind.serviceUnavailable &&
          issue != NetworkIssueKind.serverError) {
        return MarkDoseResult.failed;
      }

      try {
        await queue.enqueue(
          PendingDoseLog(
            planId: planId,
            scheduledTime: scheduledTime,
            status: status,
            occurrenceId: occurrenceId,
            queuedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        final current = state.asData?.value;
        if (current != null) {
          state = AsyncValue.data(
            _replaceStatuses(current, {occurrenceId: status}),
          );
        }

        return MarkDoseResult.queuedOffline;
      } catch (_) {
        return MarkDoseResult.failed;
      }
    }
  }

  TodaySchedule _replaceStatuses(
    TodaySchedule schedule,
    Map<String, String> statuses,
  ) {
    final updatedDoses = schedule.doses.map((dose) {
      final nextStatus = statuses[dose.occurrenceId];
      if (nextStatus == null) {
        return dose;
      }
      return dose.copyWith(status: nextStatus);
    }).toList();

    return schedule.copyWith(doses: updatedDoses).recount();
  }

  Future<void> clearForCurrentUser() async {
    final cache = ref.read(todayScheduleCacheProvider);
    final queue = ref.read(offlineDoseQueueProvider);
    await cache.clearCurrentUser();
    await queue.clearCurrentUser();
    state = const AsyncValue.data(TodaySchedule.empty());
  }

  void resetInMemory() {
    state = const AsyncValue.data(TodaySchedule.empty());
  }

  Future<void> clearAllCaches() async {
    final cache = ref.read(todayScheduleCacheProvider);
    final queue = ref.read(offlineDoseQueueProvider);
    await cache.clearAllUsers();
    await queue.clearAllUsers();
    state = const AsyncValue.data(TodaySchedule.empty());
  }
}

final todayScheduleNotifierProvider =
    AsyncNotifierProvider<TodayScheduleNotifier, TodaySchedule>(
      TodayScheduleNotifier.new,
    );
