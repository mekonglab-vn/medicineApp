import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/create_plan/domain/plan.dart';
import '../../features/home/domain/today_schedule.dart';
import '../../l10n/app_localizations.dart';

const _notificationChannelId = 'medicine_plan_channel';
const _debugNotificationPlanId = '__debug_plan__';
const _takenActionId = 'taken';
const _iosDoseCategoryId = 'dose_actions';

enum ReminderStage { pre30, due, late15, late30, late45 }

enum NotificationSyncMode { passive, force }

class NotificationActionEvent {
  const NotificationActionEvent({
    required this.actionId,
    required this.planId,
    required this.occurrenceId,
    required this.scheduledTime,
    required this.kind,
    required this.title,
  });

  final String actionId;
  final String planId;
  final String occurrenceId;
  final String scheduledTime;
  final String kind;
  final String title;

  bool get isTakenAction => actionId == _takenActionId;
}

class ScheduledReminderSnapshot {
  const ScheduledReminderSnapshot({
    required this.id,
    required this.planId,
    required this.occurrenceId,
    required this.kind,
    required this.title,
    required this.scheduledRaw,
    required this.scheduledLocal,
    required this.includesTakenAction,
  });

  final int id;
  final String planId;
  final String occurrenceId;
  final String kind;
  final String title;
  final String scheduledRaw;
  final DateTime? scheduledLocal;
  final bool includesTakenAction;
}

const _rollingWindowDays = 3;

class _PlanDateWindow {
  const _PlanDateWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _ReminderCandidate {
  const _ReminderCandidate({
    required this.uniqueKey,
    required this.planId,
    required this.occurrenceId,
    required this.kind,
    required this.when,
    required this.title,
    required this.body,
    required this.payload,
    required this.includeTakenAction,
  });

  final String uniqueKey;
  final String planId;
  final String occurrenceId;
  final String kind;
  final DateTime when;
  final String title;
  final String body;
  final String payload;
  final bool includeTakenAction;
}

class _PlanReminderBuildResult {
  const _PlanReminderBuildResult({
    required this.candidates,
    required this.desiredKeys,
  });

  final List<_ReminderCandidate> candidates;
  final Set<String> desiredKeys;
}

class _PendingPlanNotification {
  const _PendingPlanNotification({
    required this.id,
    required this.planId,
    required this.uniqueKey,
  });

  final int id;
  final String planId;
  final String? uniqueKey;
}

class _PlanSyncSnapshot {
  const _PlanSyncSnapshot({
    required this.planDigest,
    required this.windowStartKey,
    required this.windowEndKey,
  });

  final String planDigest;
  final String windowStartKey;
  final String windowEndKey;
}

class _PlanSyncOperationResult {
  const _PlanSyncOperationResult({
    required this.desiredCount,
    required this.cancelledCount,
    required this.scheduledCount,
  });

  final int desiredCount;
  final int cancelledCount;
  final int scheduledCount;
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const String _androidNotificationIcon = 'ic_stat_notification';

  factory NotificationService() => instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<NotificationActionEvent> _actionController =
      StreamController<NotificationActionEvent>.broadcast();
  final List<NotificationActionEvent> _pendingLaunchEvents = [];
  static const Duration _passiveSyncInterval = Duration(minutes: 10);
  bool _initialized = false;
  bool _syncDirty = true;
  DateTime? _lastSyncAt;
  String? _lastSyncDayKey;
  String? _lastPlansDigest;
  Future<void>? _syncInFlight;
  final Map<String, _PlanSyncSnapshot> _planSyncSnapshots =
      <String, _PlanSyncSnapshot>{};

  AppLocalizations get _l10n => lookupAppLocalizations(const Locale('vi'));

  Stream<NotificationActionEvent> get actionEvents => _actionController.stream;

  List<NotificationActionEvent> takePendingLaunchEvents() {
    final pending = List<NotificationActionEvent>.from(_pendingLaunchEvents);
    _pendingLaunchEvents.clear();
    return pending;
  }

  AndroidNotificationDetails _androidDetails({
    bool includeTakenAction = false,
  }) {
    return AndroidNotificationDetails(
      _notificationChannelId,
      _l10n.notificationChannelName,
      channelDescription: _l10n.notificationChannelDescription,
      icon: _androidNotificationIcon,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ticker: 'Nhac uong thuoc',
      playSound: true,
      enableVibration: true,
      actions: includeTakenAction
          ? <AndroidNotificationAction>[
              const AndroidNotificationAction(
                _takenActionId,
                'Đã uống',
                showsUserInterface: true,
                cancelNotification: true,
              ),
            ]
          : null,
    );
  }

  DarwinNotificationDetails _iosDetails({bool includeTakenAction = false}) {
    return DarwinNotificationDetails(
      categoryIdentifier: includeTakenAction ? _iosDoseCategoryId : null,
    );
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb) {
      _initialized = true;
      return;
    }

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const androidSettings = AndroidInitializationSettings(
      _androidNotificationIcon,
    );
    final iosSettings = DarwinInitializationSettings(
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          _iosDoseCategoryId,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              _takenActionId,
              'Đã uống',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          _notificationChannelId,
          _l10n.notificationChannelName,
          description: _l10n.notificationChannelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
      );
    }

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _queueNotificationEvent(launchResponse);
    }

    _initialized = true;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    _queueNotificationEvent(response);
  }

  void _queueNotificationEvent(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }

    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final event = NotificationActionEvent(
        actionId: response.actionId ?? '',
        planId: json['planId']?.toString() ?? '',
        occurrenceId: json['occurrenceId']?.toString() ?? '',
        scheduledTime: json['scheduledTime']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'unknown',
        title: json['title']?.toString() ?? '',
      );
      if (event.occurrenceId.isEmpty || event.planId.isEmpty) {
        return;
      }

      if (_actionController.hasListener) {
        _actionController.add(event);
      } else {
        _pendingLaunchEvents.add(event);
      }
    } catch (_) {
      return;
    }
  }

  int _hashId(String text) {
    var hash = 17;
    for (final codeUnit in text.codeUnits) {
      hash = 37 * hash + codeUnit;
    }
    return hash.abs() % 2147483647;
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void markNotificationsDirty([String reason = '']) {
    _syncDirty = true;
    if (kDebugMode) {
      final suffix = reason.trim().isEmpty ? '' : ' ($reason)';
      debugPrint('[NotificationService] Mark sync dirty$suffix');
    }
  }

  String _buildPlanDigest(Plan plan) {
    final buffer = StringBuffer()
      ..write(plan.startDate)
      ..write('|')
      ..write(plan.endDate ?? '')
      ..write('|')
      ..write(plan.isActive ? '1' : '0')
      ..write('|')
      ..write(plan.totalDays ?? 0)
      ..write('|');

    final sortedSlots = List<PlanSlot>.from(plan.slots)
      ..sort((a, b) => a.time.compareTo(b.time));
    for (final slot in sortedSlots) {
      buffer
        ..write(slot.time)
        ..write(':');
      final sortedItems = List<PlanSlotMedication>.from(slot.items)
        ..sort((a, b) {
          final byName = a.drugName.compareTo(b.drugName);
          if (byName != 0) {
            return byName;
          }
          return (a.drugId ?? '').compareTo(b.drugId ?? '');
        });
      for (final item in sortedItems) {
        buffer
          ..write(item.drugName)
          ..write('#')
          ..write(item.pills)
          ..write(';');
      }
      buffer.write('|');
    }

    return buffer.toString();
  }

  String _buildPlansDigest(List<Plan> plans) {
    final activePlans = plans.where((plan) => plan.isCurrentPlan).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final buffer = StringBuffer();

    for (final plan in activePlans) {
      buffer
        ..write(plan.id)
        ..write('|')
        ..write(_buildPlanDigest(plan))
        ..write('||');
    }

    return buffer.toString();
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  _PlanDateWindow? _resolvePlanDateWindow(Plan plan, DateTime now) {
    final today = _normalizeDate(now);
    final rollingWindowEnd = today.add(Duration(days: _rollingWindowDays - 1));

    final parsedStart = DateTime.tryParse(plan.startDate);
    final planStart = parsedStart != null ? _normalizeDate(parsedStart) : today;

    final parsedEnd = plan.parsedEndDate;
    final totalDays = plan.totalDays ?? 30;
    final safeTotalDays = totalDays < 1 ? 1 : totalDays;
    var planEnd = parsedEnd != null
        ? _normalizeDate(parsedEnd)
        : planStart.add(Duration(days: safeTotalDays - 1));

    if (planEnd.isBefore(planStart)) {
      planEnd = planStart;
    }

    final windowStart = planStart.isAfter(today) ? planStart : today;
    final windowEnd = planEnd.isBefore(rollingWindowEnd)
        ? planEnd
        : rollingWindowEnd;

    if (windowStart.isAfter(windowEnd)) {
      return null;
    }

    return _PlanDateWindow(start: windowStart, end: windowEnd);
  }

  _PlanSyncSnapshot _buildPlanSyncSnapshot(Plan plan, _PlanDateWindow? window) {
    return _PlanSyncSnapshot(
      planDigest: _buildPlanDigest(plan),
      windowStartKey: window != null ? _dateKey(window.start) : '',
      windowEndKey: window != null ? _dateKey(window.end) : '',
    );
  }

  String _slotBody(PlanSlot slot) {
    if (slot.items.isEmpty) {
      return _l10n.notificationDefaultBody;
    }

    return slot.items
        .map((item) => '${item.drugName} (${item.pills} viên)')
        .join(', ');
  }

  String _stageKind(ReminderStage stage) {
    return switch (stage) {
      ReminderStage.pre30 => 'pre_30',
      ReminderStage.due => 'due',
      ReminderStage.late15 => 'late_15',
      ReminderStage.late30 => 'late_30',
      ReminderStage.late45 => 'late_45',
    };
  }

  String _formatLocalDateTime(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    final ss = dateTime.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  String _titleForStage(ReminderStage stage, String timeLabel) {
    return switch (stage) {
      ReminderStage.pre30 => 'Sắp đến giờ uống thuốc ($timeLabel)',
      ReminderStage.due => 'Đến giờ uống thuốc ($timeLabel)',
      ReminderStage.late15 => 'Bạn chưa xác nhận đã uống ($timeLabel)',
      ReminderStage.late30 => 'Liều thuốc đang trễ 30 phút ($timeLabel)',
      ReminderStage.late45 => 'Liều thuốc sắp bị tính là quên ($timeLabel)',
    };
  }

  String _bodyForStage(
    ReminderStage stage, {
    required String timeLabel,
    required String medicationSummary,
  }) {
    return switch (stage) {
      ReminderStage.pre30 =>
        'Còn 30 phút tới liều $timeLabel. Thuốc cần uống: $medicationSummary.',
      ReminderStage.due =>
        'Đến giờ $timeLabel. Thuốc cần uống: $medicationSummary. Sau khi uống xong, hãy nhấn "Đã uống".',
      ReminderStage.late15 =>
        'Liều $timeLabel đã trễ 15 phút. Thuốc cần uống: $medicationSummary. Hãy uống và nhấn "Đã uống".',
      ReminderStage.late30 =>
        'Liều $timeLabel đã trễ 30 phút. Thuốc cần uống: $medicationSummary. Vui lòng xác nhận "Đã uống" ngay khi dùng thuốc.',
      ReminderStage.late45 =>
        'Liều $timeLabel đã trễ 45 phút và sắp bị tính là quên. Thuốc: $medicationSummary. Hãy nhấn "Đã uống" nếu bạn vừa dùng thuốc.',
    };
  }

  String _payload({
    required String planId,
    required String occurrenceId,
    required String scheduledTime,
    required String kind,
    required String title,
  }) {
    return jsonEncode({
      'planId': planId,
      'occurrenceId': occurrenceId,
      'scheduledTime': scheduledTime,
      'kind': kind,
      'title': title,
    });
  }

  String _buildReminderUniqueKey({
    required String occurrenceId,
    required String kind,
  }) {
    return '$occurrenceId:$kind';
  }

  String? _extractReminderUniqueKeyFromPayload(Map<String, dynamic>? payload) {
    final occurrenceId = payload?['occurrenceId']?.toString() ?? '';
    final kind = payload?['kind']?.toString() ?? '';
    if (occurrenceId.isEmpty || kind.isEmpty) {
      return null;
    }
    return _buildReminderUniqueKey(occurrenceId: occurrenceId, kind: kind);
  }

  Map<String, List<_PendingPlanNotification>> _indexPendingByPlan(
    List<PendingNotificationRequest> pending,
  ) {
    final byPlan = <String, List<_PendingPlanNotification>>{};

    for (final req in pending) {
      final payload = _decodePayload(req.payload);
      final planId = payload?['planId']?.toString() ?? '';
      if (planId.isEmpty || planId == _debugNotificationPlanId) {
        continue;
      }

      byPlan
          .putIfAbsent(planId, () => <_PendingPlanNotification>[])
          .add(
            _PendingPlanNotification(
              id: req.id,
              planId: planId,
              uniqueKey: _extractReminderUniqueKeyFromPayload(payload),
            ),
          );
    }

    return byPlan;
  }

  _PlanReminderBuildResult _buildPlanReminderCandidates(
    Plan plan, {
    required DateTime now,
    _PlanDateWindow? window,
  }) {
    final resolvedWindow = window ?? _resolvePlanDateWindow(plan, now);
    if (resolvedWindow == null || plan.slots.isEmpty) {
      return const _PlanReminderBuildResult(
        candidates: <_ReminderCandidate>[],
        desiredKeys: <String>{},
      );
    }

    final candidates = <_ReminderCandidate>[];
    final desiredKeys = <String>{};

    for (
      var current = resolvedWindow.start;
      !current.isAfter(resolvedWindow.end);
      current = current.add(const Duration(days: 1))
    ) {
      final dateKey = _dateKey(current);

      for (final slot in plan.slots) {
        final parts = slot.time.split(':');
        if (parts.length != 2) {
          continue;
        }

        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) {
          continue;
        }

        final scheduled = DateTime(
          current.year,
          current.month,
          current.day,
          hour,
          minute,
        );
        final occurrenceId = '${plan.id}:$dateKey:${slot.time}';
        final scheduledTime = scheduled.toUtc().toIso8601String();
        final medicationSummary = _slotBody(slot);
        final timeLabel = slot.time;

        void pushStage(ReminderStage stage, DateTime when) {
          if (!when.isAfter(now)) {
            return;
          }

          final kind = _stageKind(stage);
          final uniqueKey = _buildReminderUniqueKey(
            occurrenceId: occurrenceId,
            kind: kind,
          );
          final title = _titleForStage(stage, timeLabel);

          desiredKeys.add(uniqueKey);
          candidates.add(
            _ReminderCandidate(
              uniqueKey: uniqueKey,
              planId: plan.id,
              occurrenceId: occurrenceId,
              kind: kind,
              when: when,
              title: title,
              body: _bodyForStage(
                stage,
                timeLabel: timeLabel,
                medicationSummary: medicationSummary,
              ),
              payload: _payload(
                planId: plan.id,
                occurrenceId: occurrenceId,
                scheduledTime: scheduledTime,
                kind: kind,
                title: title,
              ),
              includeTakenAction: stage != ReminderStage.pre30,
            ),
          );
        }

        pushStage(
          ReminderStage.pre30,
          scheduled.subtract(const Duration(minutes: 30)),
        );
        pushStage(ReminderStage.due, scheduled);
        pushStage(
          ReminderStage.late15,
          scheduled.add(const Duration(minutes: 15)),
        );
        pushStage(
          ReminderStage.late30,
          scheduled.add(const Duration(minutes: 30)),
        );
        pushStage(
          ReminderStage.late45,
          scheduled.add(const Duration(minutes: 45)),
        );
      }
    }

    return _PlanReminderBuildResult(
      candidates: candidates,
      desiredKeys: desiredKeys,
    );
  }

  Future<int> _scheduleCandidates(
    Iterable<_ReminderCandidate> candidates,
  ) async {
    var scheduledCount = 0;
    for (final candidate in candidates) {
      await _scheduleReminder(
        uniqueKey: candidate.uniqueKey,
        when: candidate.when,
        title: candidate.title,
        body: candidate.body,
        payload: candidate.payload,
        includeTakenAction: candidate.includeTakenAction,
      );
      scheduledCount += 1;
    }
    return scheduledCount;
  }

  Future<_PlanSyncOperationResult> _syncPlanDelta({
    required Plan plan,
    required DateTime now,
    required List<_PendingPlanNotification> pendingForPlan,
    required bool rewriteExisting,
    _PlanDateWindow? window,
  }) async {
    final buildResult = _buildPlanReminderCandidates(
      plan,
      now: now,
      window: window,
    );

    final existingKeys = <String>{
      for (final pending in pendingForPlan)
        if (pending.uniqueKey != null) pending.uniqueKey!,
    };
    var cancelledCount = 0;
    for (final pending in pendingForPlan) {
      final key = pending.uniqueKey;
      if (key == null || !buildResult.desiredKeys.contains(key)) {
        await _plugin.cancel(pending.id);
        cancelledCount += 1;
        if (key != null) {
          existingKeys.remove(key);
        }
      }
    }

    final candidatesToSchedule = rewriteExisting
        ? buildResult.candidates
        : buildResult.candidates.where(
            (candidate) => !existingKeys.contains(candidate.uniqueKey),
          );
    final scheduledCount = await _scheduleCandidates(candidatesToSchedule);
    return _PlanSyncOperationResult(
      desiredCount: buildResult.desiredKeys.length,
      cancelledCount: cancelledCount,
      scheduledCount: scheduledCount,
    );
  }

  Future<_PlanSyncOperationResult> _syncPlanFallbackSafe({
    required Plan plan,
    required DateTime now,
    required List<_PendingPlanNotification> pendingForPlan,
    _PlanDateWindow? window,
  }) async {
    var cancelledCount = 0;
    for (final pending in pendingForPlan) {
      await _plugin.cancel(pending.id);
      cancelledCount += 1;
    }

    final buildResult = _buildPlanReminderCandidates(
      plan,
      now: now,
      window: window,
    );
    final scheduledCount = await _scheduleCandidates(buildResult.candidates);
    return _PlanSyncOperationResult(
      desiredCount: buildResult.desiredKeys.length,
      cancelledCount: cancelledCount,
      scheduledCount: scheduledCount,
    );
  }

  Future<void> _scheduleReminder({
    required String uniqueKey,
    required DateTime when,
    required String title,
    required String body,
    required String payload,
    required bool includeTakenAction,
  }) async {
    if (!when.isAfter(DateTime.now())) {
      return;
    }

    final id = _hashId(uniqueKey);
    final scheduleAt = tz.TZDateTime.from(when, tz.local);
    final details = NotificationDetails(
      android: _androidDetails(includeTakenAction: includeTakenAction),
      iOS: _iosDetails(includeTakenAction: includeTakenAction),
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduleAt,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
      if (kDebugMode) {
        debugPrint(
          '[NotificationService] Scheduled($id) $uniqueKey at '
          '${scheduleAt.toLocal().toIso8601String()}',
        );
      }
    } on PlatformException catch (e) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            scheduleAt,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: payload,
          );
          if (kDebugMode) {
            debugPrint(
              '[NotificationService] Fallback to inexact schedule for '
              '$uniqueKey (${e.code}: ${e.message})',
            );
          }
          return;
        } on PlatformException catch (fallbackError) {
          if (kDebugMode) {
            debugPrint(
              '[NotificationService] Fallback schedule failed for '
              '$uniqueKey: ${fallbackError.code} ${fallbackError.message}',
            );
          }
        }
      }
      if (kDebugMode) {
        debugPrint(
          '[NotificationService] zonedSchedule skipped for $uniqueKey: '
          '${e.code} ${e.message}',
        );
      }
    }
  }

  Future<void> _showReminderNow({
    required String uniqueKey,
    required String title,
    required String body,
    required String payload,
    required bool includeTakenAction,
  }) async {
    await _plugin.show(
      _hashId(uniqueKey),
      title,
      body,
      NotificationDetails(
        android: _androidDetails(includeTakenAction: includeTakenAction),
        iOS: _iosDetails(includeTakenAction: includeTakenAction),
      ),
      payload: payload,
    );
  }

  Future<void> schedulePlanNotifications(
    Plan plan, {
    bool clearExisting = true,
  }) async {
    await initialize();
    if (kIsWeb || plan.hasEnded) {
      return;
    }

    if (clearExisting) {
      await cancelPlanNotifications(plan.id);
    }

    final buildResult = _buildPlanReminderCandidates(plan, now: DateTime.now());
    await _scheduleCandidates(buildResult.candidates);
  }

  Future<void> scheduleDosesFromTodaySummary(List<TodayDose> doses) async {
    await initialize();
    if (kIsWeb) {
      return;
    }

    final now = DateTime.now();
    final pendingByOccurrence = <String, TodayDose>{
      for (final dose in doses)
        if (dose.status == 'pending' && dose.occurrenceId.isNotEmpty)
          dose.occurrenceId: dose,
    };

    if (pendingByOccurrence.isEmpty) {
      return;
    }

    for (final entry in pendingByOccurrence.entries) {
      final occurrenceId = entry.key;
      final dose = entry.value;

      final scheduledLocal = dose.scheduledLocalDateTime;
      if (scheduledLocal == null) {
        continue;
      }

      final planId = dose.planId;
      final titleBase = dose.title?.trim().isNotEmpty == true
          ? dose.title!.trim()
          : dose.drugName;

      final medicationSummary = dose.medications.isNotEmpty
          ? dose.medications
                .map((item) => '${item.drugName} (${item.pills} viên)')
                .join(', ')
          : dose.drugName;

      Future<void> scheduleSummaryStage({
        required ReminderStage stage,
        required DateTime when,
      }) {
        final timeLabel = dose.time;
        final title = _titleForStage(stage, timeLabel);
        return _scheduleReminder(
          uniqueKey: '$occurrenceId:${_stageKind(stage)}',
          when: when,
          title: title,
          body: _bodyForStage(
            stage,
            timeLabel: timeLabel,
            medicationSummary: medicationSummary,
          ),
          payload: _payload(
            planId: planId,
            occurrenceId: occurrenceId,
            scheduledTime: dose.scheduledTime,
            kind: _stageKind(stage),
            title: titleBase,
          ),
          includeTakenAction: stage != ReminderStage.pre30,
        );
      }

      final pre = scheduledLocal.subtract(const Duration(minutes: 30));
      final due = scheduledLocal;
      final late15 = scheduledLocal.add(const Duration(minutes: 15));
      final late30 = scheduledLocal.add(const Duration(minutes: 30));
      final late45 = scheduledLocal.add(const Duration(minutes: 45));

      if (pre.isAfter(now)) {
        await scheduleSummaryStage(stage: ReminderStage.pre30, when: pre);
      }
      if (due.isAfter(now)) {
        await scheduleSummaryStage(stage: ReminderStage.due, when: due);
      }
      if (late15.isAfter(now)) {
        await scheduleSummaryStage(stage: ReminderStage.late15, when: late15);
      }
      if (late30.isAfter(now)) {
        await scheduleSummaryStage(stage: ReminderStage.late30, when: late30);
      }
      if (late45.isAfter(now)) {
        await scheduleSummaryStage(stage: ReminderStage.late45, when: late45);
      }
    }
  }

  Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return null;
    }

    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> cancelOccurrenceNotifications(String occurrenceId) async {
    await initialize();
    if (kIsWeb) {
      return;
    }

    final pending = await _plugin.pendingNotificationRequests();
    for (final req in pending) {
      final payload = _decodePayload(req.payload);
      if (payload?['occurrenceId']?.toString() == occurrenceId) {
        await _plugin.cancel(req.id);
      }
    }
  }

  Future<void> cancelPlanNotifications(String planId) async {
    await initialize();
    if (kIsWeb) {
      return;
    }

    final pending = await _plugin.pendingNotificationRequests();
    for (final req in pending) {
      final payload = _decodePayload(req.payload);
      if (payload?['planId']?.toString() == planId) {
        await _plugin.cancel(req.id);
      }
    }
  }

  Future<void> rescheduleAllPlans(
    List<Plan> plans, {
    NotificationSyncMode mode = NotificationSyncMode.force,
    String reason = 'unspecified',
  }) async {
    await initialize();
    if (kIsWeb) {
      return;
    }

    final inFlight = _syncInFlight;
    if (inFlight != null) {
      if (kDebugMode) {
        debugPrint(
          '[NotificationService] Wait for in-flight sync '
          '(mode=${mode.name}, reason=$reason)',
        );
      }
      await inFlight;
      if (mode == NotificationSyncMode.passive) {
        if (kDebugMode) {
          debugPrint(
            '[NotificationService] Skip passive sync because '
            'a previous sync just finished (reason=$reason)',
          );
        }
        return;
      }
    }

    final future = _rescheduleAllPlansInternal(
      plans,
      mode: mode,
      reason: reason,
    );
    _syncInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_syncInFlight, future)) {
        _syncInFlight = null;
      }
    }
  }

  Future<void> _rescheduleAllPlansInternal(
    List<Plan> plans, {
    required NotificationSyncMode mode,
    required String reason,
  }) async {
    final activePlans = plans.where((plan) => plan.isCurrentPlan).toList();
    final now = DateTime.now();
    final nowDayKey = _dateKey(now);
    final currentDigest = _buildPlansDigest(activePlans);
    final isForceMode = mode == NotificationSyncMode.force;

    final hasNeverSynced = _lastSyncAt == null || _lastPlansDigest == null;
    final dayChanged = _lastSyncDayKey != null && _lastSyncDayKey != nowDayKey;
    final plansChanged =
        _lastPlansDigest != null && _lastPlansDigest != currentDigest;
    final exceededInterval =
        _lastSyncAt != null &&
        now.difference(_lastSyncAt!) >= _passiveSyncInterval;

    final shouldRun =
        isForceMode ||
        _syncDirty ||
        hasNeverSynced ||
        dayChanged ||
        plansChanged ||
        exceededInterval;

    if (!shouldRun) {
      if (kDebugMode) {
        debugPrint(
          '[NotificationService] Skip sync '
          '(mode=${mode.name}, reason=$reason, dirty=$_syncDirty, '
          'dayChanged=$dayChanged, plansChanged=$plansChanged, '
          'exceededInterval=$exceededInterval)',
        );
      }
      return;
    }

    final startedAt = DateTime.now();
    final activePlanIds = activePlans.map((plan) => plan.id).toSet();
    final pending = await _plugin.pendingNotificationRequests();
    final pendingByPlan = _indexPendingByPlan(pending);

    var cancelledOrphanCount = 0;
    for (final entry in pendingByPlan.entries) {
      if (activePlanIds.contains(entry.key)) {
        continue;
      }
      for (final pendingForOrphan in entry.value) {
        await _plugin.cancel(pendingForOrphan.id);
        cancelledOrphanCount += 1;
      }
    }

    final staleSnapshotPlanIds = _planSyncSnapshots.keys
        .where((planId) => !activePlanIds.contains(planId))
        .toList();
    for (final planId in staleSnapshotPlanIds) {
      _planSyncSnapshots.remove(planId);
    }

    final windowsByPlanId = <String, _PlanDateWindow?>{};
    final snapshotsByPlanId = <String, _PlanSyncSnapshot>{};
    final plansToSync = <Plan>[];
    var plansSkipped = 0;

    for (final plan in activePlans) {
      final window = _resolvePlanDateWindow(plan, now);
      windowsByPlanId[plan.id] = window;

      final nextSnapshot = _buildPlanSyncSnapshot(plan, window);
      snapshotsByPlanId[plan.id] = nextSnapshot;
      final previousSnapshot = _planSyncSnapshots[plan.id];

      final snapshotChanged =
          previousSnapshot == null ||
          previousSnapshot.planDigest != nextSnapshot.planDigest ||
          previousSnapshot.windowStartKey != nextSnapshot.windowStartKey ||
          previousSnapshot.windowEndKey != nextSnapshot.windowEndKey;

      final shouldSyncPlan =
          isForceMode || hasNeverSynced || _syncDirty || snapshotChanged;

      if (shouldSyncPlan) {
        plansToSync.add(plan);
      } else {
        plansSkipped += 1;
      }
    }

    var desiredCount = 0;
    var scheduledCount = 0;
    var cancelledStaleCount = 0;
    var fallbackPlans = 0;
    var fallbackFailures = 0;

    for (final plan in plansToSync) {
      final pendingForPlan =
          pendingByPlan[plan.id] ?? const <_PendingPlanNotification>[];
      final window = windowsByPlanId[plan.id];

      try {
        final deltaResult = await _syncPlanDelta(
          plan: plan,
          now: now,
          pendingForPlan: pendingForPlan,
          rewriteExisting: isForceMode || _syncDirty || hasNeverSynced,
          window: window,
        );
        desiredCount += deltaResult.desiredCount;
        cancelledStaleCount += deltaResult.cancelledCount;
        scheduledCount += deltaResult.scheduledCount;
        _planSyncSnapshots[plan.id] = snapshotsByPlanId[plan.id]!;
      } catch (e, st) {
        fallbackPlans += 1;
        if (kDebugMode) {
          debugPrint(
            '[NotificationService] Delta sync failed for plan=${plan.id}; '
            'fallback safe sync. Error: $e',
          );
          debugPrint('$st');
        }

        try {
          final fallbackResult = await _syncPlanFallbackSafe(
            plan: plan,
            now: now,
            pendingForPlan: pendingForPlan,
            window: window,
          );
          desiredCount += fallbackResult.desiredCount;
          cancelledStaleCount += fallbackResult.cancelledCount;
          scheduledCount += fallbackResult.scheduledCount;
          _planSyncSnapshots[plan.id] = snapshotsByPlanId[plan.id]!;
        } catch (fallbackError, fallbackSt) {
          fallbackFailures += 1;
          if (kDebugMode) {
            debugPrint(
              '[NotificationService] Fallback sync failed for plan=${plan.id}: '
              '$fallbackError',
            );
            debugPrint('$fallbackSt');
          }
        }
      }
    }

    _lastSyncAt = DateTime.now();
    _lastSyncDayKey = _dateKey(_lastSyncAt!);
    _lastPlansDigest = currentDigest;
    _syncDirty = fallbackFailures > 0;

    if (kDebugMode) {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        '[NotificationService] Run sync '
        '(mode=${mode.name}, reason=$reason, activePlans=${activePlans.length}, '
        'plansToSync=${plansToSync.length}, plansSkipped=$plansSkipped, '
        'pending=${pending.length}, desiredCount=$desiredCount, '
        'scheduled=$scheduledCount, cancelledStale=$cancelledStaleCount, '
        'cancelledOrphan=$cancelledOrphanCount, fallbackPlans=$fallbackPlans, '
        'fallbackFailures=$fallbackFailures, elapsedMs=$elapsedMs)',
      );
    }
  }

  Future<bool> hasPermissions() async {
    if (kIsWeb) {
      return false;
    }
    await initialize();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin == null) {
        return false;
      }

      final notificationsEnabled =
          await androidPlugin.areNotificationsEnabled() ?? false;
      if (!notificationsEnabled) {
        return false;
      }

      final exactAlarmsEnabled =
          await androidPlugin.canScheduleExactNotifications() ?? false;
      if (!exactAlarmsEnabled) {
        return false;
      }

      return true;
    }
    return true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) {
      return;
    }
    await initialize();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin == null) {
        return;
      }

      final notificationsEnabled =
          await androidPlugin.areNotificationsEnabled() ?? false;
      if (!notificationsEnabled) {
        await androidPlugin.requestNotificationsPermission();
      }

      final exactAlarmsEnabled =
          await androidPlugin.canScheduleExactNotifications() ?? false;
      if (!exactAlarmsEnabled) {
        await androidPlugin.requestExactAlarmsPermission();
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> cancelAllNotifications() async {
    await initialize();
    if (kIsWeb) {
      return;
    }
    await _plugin.cancelAll();
  }

  Future<void> sendDebugNotificationsBurst() async {
    await initialize();
    if (kIsWeb) {
      return;
    }

    final now = DateTime.now();
    final base = now.add(const Duration(seconds: 20));
    const debugTimeLabel = '18:00';
    const debugMedicationSummary = 'Paracetamol 500mg (1 viên)';

    await cancelPlanNotifications(_debugNotificationPlanId);

    Future<void> scheduleAt({
      required String key,
      required DateTime when,
      required ReminderStage stage,
    }) {
      final title = _titleForStage(stage, debugTimeLabel);
      return _scheduleReminder(
        uniqueKey: key,
        when: when,
        title: title,
        body: _bodyForStage(
          stage,
          timeLabel: debugTimeLabel,
          medicationSummary: debugMedicationSummary,
        ),
        includeTakenAction: stage != ReminderStage.pre30,
        payload: _payload(
          planId: _debugNotificationPlanId,
          occurrenceId: '$key:${when.millisecondsSinceEpoch}',
          scheduledTime: when.toUtc().toIso8601String(),
          kind: _stageKind(stage),
          title: title,
        ),
      );
    }

    final preTitle = _titleForStage(ReminderStage.pre30, debugTimeLabel);
    await _showReminderNow(
      uniqueKey: 'debug-pre-now',
      title: preTitle,
      body: _bodyForStage(
        ReminderStage.pre30,
        timeLabel: debugTimeLabel,
        medicationSummary: debugMedicationSummary,
      ),
      includeTakenAction: false,
      payload: _payload(
        planId: _debugNotificationPlanId,
        occurrenceId: 'debug-pre-now:${now.millisecondsSinceEpoch}',
        scheduledTime: now.toUtc().toIso8601String(),
        kind: _stageKind(ReminderStage.pre30),
        title: preTitle,
      ),
    );

    await scheduleAt(key: 'debug-due', when: base, stage: ReminderStage.due);
    await scheduleAt(
      key: 'debug-followup-15',
      when: base.add(const Duration(seconds: 20)),
      stage: ReminderStage.late15,
    );
    await scheduleAt(
      key: 'debug-followup-30',
      when: base.add(const Duration(seconds: 40)),
      stage: ReminderStage.late30,
    );
    await scheduleAt(
      key: 'debug-followup-45',
      when: base.add(const Duration(seconds: 60)),
      stage: ReminderStage.late45,
    );
  }

  Future<void> sendDebugNotificationsMinuteScale() async {
    await initialize();
    if (kIsWeb) {
      return;
    }

    final now = DateTime.now();
    final preAt = now.add(const Duration(minutes: 1));
    final dueAt = now.add(const Duration(minutes: 2));
    final late15At = now.add(const Duration(minutes: 3));
    final late30At = now.add(const Duration(minutes: 4));
    final late45At = now.add(const Duration(minutes: 5));

    const debugTimeLabel = '20:00';
    const debugMedicationSummary = 'Paracetamol 500mg (1 viên)';

    await cancelPlanNotifications(_debugNotificationPlanId);

    Future<void> scheduleAt({
      required String key,
      required DateTime when,
      required ReminderStage stage,
    }) {
      final title = _titleForStage(stage, debugTimeLabel);
      return _scheduleReminder(
        uniqueKey: key,
        when: when,
        title: title,
        body: _bodyForStage(
          stage,
          timeLabel: debugTimeLabel,
          medicationSummary: debugMedicationSummary,
        ),
        includeTakenAction: stage != ReminderStage.pre30,
        payload: _payload(
          planId: _debugNotificationPlanId,
          occurrenceId: '$key:${when.millisecondsSinceEpoch}',
          scheduledTime: when.toUtc().toIso8601String(),
          kind: _stageKind(stage),
          title: title,
        ),
      );
    }

    await scheduleAt(
      key: 'debug-minute-pre',
      when: preAt,
      stage: ReminderStage.pre30,
    );
    await scheduleAt(
      key: 'debug-minute-due',
      when: dueAt,
      stage: ReminderStage.due,
    );
    await scheduleAt(
      key: 'debug-minute-late15',
      when: late15At,
      stage: ReminderStage.late15,
    );
    await scheduleAt(
      key: 'debug-minute-late30',
      when: late30At,
      stage: ReminderStage.late30,
    );
    await scheduleAt(
      key: 'debug-minute-late45',
      when: late45At,
      stage: ReminderStage.late45,
    );
  }

  Future<List<ScheduledReminderSnapshot>> getScheduledReminders({
    String? planId,
  }) async {
    await initialize();
    if (kIsWeb) {
      return const [];
    }

    final pending = await _plugin.pendingNotificationRequests();
    final snapshots = <ScheduledReminderSnapshot>[];

    for (final req in pending) {
      final payload = _decodePayload(req.payload);
      final payloadPlanId = payload?['planId']?.toString() ?? '';
      if (payloadPlanId.isEmpty) {
        continue;
      }
      if (planId != null && planId.isNotEmpty && payloadPlanId != planId) {
        continue;
      }

      final kind = payload?['kind']?.toString() ?? 'unknown';
      final scheduledRaw = payload?['scheduledTime']?.toString() ?? '';
      final scheduledLocal = DateTime.tryParse(scheduledRaw)?.toLocal();

      snapshots.add(
        ScheduledReminderSnapshot(
          id: req.id,
          planId: payloadPlanId,
          occurrenceId: payload?['occurrenceId']?.toString() ?? '',
          kind: kind,
          title:
              req.title ??
              payload?['title']?.toString() ??
              _l10n.notificationDefaultTitle,
          scheduledRaw: scheduledRaw,
          scheduledLocal: scheduledLocal,
          includesTakenAction: kind != _stageKind(ReminderStage.pre30),
        ),
      );
    }

    snapshots.sort((a, b) {
      final left = a.scheduledLocal;
      final right = b.scheduledLocal;

      if (left == null && right == null) {
        return a.id.compareTo(b.id);
      }
      if (left == null) {
        return 1;
      }
      if (right == null) {
        return -1;
      }

      final byTime = left.compareTo(right);
      if (byTime != 0) {
        return byTime;
      }

      return a.id.compareTo(b.id);
    });

    return snapshots;
  }

  Future<String> buildScheduledRemindersReport({
    String? planId,
    int maxItems = 60,
  }) async {
    final reminders = await getScheduledReminders(planId: planId);
    if (reminders.isEmpty) {
      return 'Không có lịch nhắc nào đang chờ trên thiết bị.';
    }

    final preview = reminders.take(maxItems).toList();
    final buffer = StringBuffer();
    buffer.writeln('Tổng số lịch nhắc đang chờ: ${reminders.length}');
    if (planId != null && planId.isNotEmpty) {
      buffer.writeln('Lọc theo planId: $planId');
    }
    buffer.writeln('');

    for (var i = 0; i < preview.length; i++) {
      final item = preview[i];
      final timeLabel = item.scheduledLocal != null
          ? _formatLocalDateTime(item.scheduledLocal!)
          : (item.scheduledRaw.isEmpty
                ? 'không có thời gian'
                : item.scheduledRaw);
      final actionLabel = item.includesTakenAction
          ? 'có nút "Đã uống"'
          : 'không có nút';

      buffer.writeln('${i + 1}. [$timeLabel] ${item.kind} | ${item.title}');
      buffer.writeln(
        '   plan=${item.planId}, occ=${item.occurrenceId}, id=${item.id}, $actionLabel',
      );
    }

    if (reminders.length > preview.length) {
      buffer.writeln('');
      buffer.writeln(
        '... và ${reminders.length - preview.length} lịch nhắc khác.',
      );
    }

    return buffer.toString().trimRight();
  }

  Future<void> showImmediateLockscreenTest() async {
    await initialize();
    if (kIsWeb) {
      return;
    }

    final now = DateTime.now();
    final title = 'Nhắc uống thuốc (màn hình khóa)';
    final body =
        'Đây là nhắc uống thuốc gửi ngay để kiểm tra hiển thị trên màn hình khóa.';

    await _plugin.show(
      _hashId('immediate-lockscreen-test-${now.millisecondsSinceEpoch}'),
      title,
      body,
      NotificationDetails(
        android: _androidDetails(includeTakenAction: false),
        iOS: _iosDetails(includeTakenAction: false),
      ),
      payload: _payload(
        planId: _debugNotificationPlanId,
        occurrenceId: 'immediate:${now.millisecondsSinceEpoch}',
        scheduledTime: now.toUtc().toIso8601String(),
        kind: 'debug_immediate',
        title: title,
      ),
    );
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
