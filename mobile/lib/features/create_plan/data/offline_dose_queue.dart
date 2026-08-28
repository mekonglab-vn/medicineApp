import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/session/current_user_store.dart';
import '../../../core/network/dio_client.dart';

class PendingDoseLog {
  const PendingDoseLog({
    required this.planId,
    required this.scheduledTime,
    required this.status,
    required this.occurrenceId,
    required this.queuedAt,
    this.note,
  });

  final String planId;
  final String scheduledTime;
  final String status;
  final String occurrenceId;
  final String queuedAt;
  final String? note;

  Map<String, dynamic> toJson() => {
    'planId': planId,
    'scheduledTime': scheduledTime,
    'status': status,
    'occurrenceId': occurrenceId,
    'queuedAt': queuedAt,
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  factory PendingDoseLog.fromJson(Map<String, dynamic> json) => PendingDoseLog(
    planId: json['planId']?.toString() ?? '',
    scheduledTime: json['scheduledTime']?.toString() ?? '',
    status: json['status']?.toString() ?? 'pending',
    occurrenceId: json['occurrenceId']?.toString() ?? '',
    queuedAt:
        json['queuedAt']?.toString() ??
        DateTime.now().toUtc().toIso8601String(),
    note: json['note']?.toString(),
  );
}

class OfflineDoseQueue {
  OfflineDoseQueue(this._dio, this._userStore);

  final Dio _dio;
  final CurrentUserStore _userStore;
  static const _storage = FlutterSecureStorage();
  static const _queuePrefix = 'offline_dose_log_queue_v2';
  static const _legacyQueueKey = 'offline_dose_log_queue_v1';

  String _keyForUser(String userId) => '${_queuePrefix}_$userId';

  DateTime _parseQueuedAt(String raw) {
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<PendingDoseLog> _dedupeByOccurrenceKeepingLatest(
    List<PendingDoseLog> items,
  ) {
    final byOccurrence = <String, PendingDoseLog>{};
    for (final item in items) {
      if (item.occurrenceId.isEmpty) {
        continue;
      }
      byOccurrence[item.occurrenceId] = item;
    }

    final deduped = byOccurrence.values.toList();
    deduped.sort(
      (left, right) => _parseQueuedAt(
        left.queuedAt,
      ).compareTo(_parseQueuedAt(right.queuedAt)),
    );
    return deduped;
  }

  Future<String?> _resolveCurrentKey() async {
    final userId = await _userStore.getCurrentUserId();
    if (userId == null || userId.isEmpty) {
      return null;
    }
    return _keyForUser(userId);
  }

  Future<void> _migrateLegacyIfNeeded(String scopedKey) async {
    final scopedValue = await _storage.read(key: scopedKey);
    if (scopedValue != null && scopedValue.isNotEmpty) {
      return;
    }

    final legacy = await _storage.read(key: _legacyQueueKey);
    if (legacy == null || legacy.isEmpty) {
      return;
    }

    await _storage.write(key: scopedKey, value: legacy);
    await _storage.delete(key: _legacyQueueKey);
  }

  Future<List<PendingDoseLog>> _loadQueueByKey(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final queue = list
          .map((e) => PendingDoseLog.fromJson(e as Map<String, dynamic>))
          .toList();
      return _dedupeByOccurrenceKeepingLatest(queue);
    } catch (_) {
      await _storage.delete(key: key);
      return const [];
    }
  }

  Future<List<PendingDoseLog>> _loadQueue() async {
    final key = await _resolveCurrentKey();
    if (key == null) {
      return const [];
    }

    await _migrateLegacyIfNeeded(key);
    return _loadQueueByKey(key);
  }

  Future<void> _saveQueue(List<PendingDoseLog> queue) async {
    final key = await _resolveCurrentKey();
    if (key == null) {
      return;
    }

    final deduped = _dedupeByOccurrenceKeepingLatest(queue);

    if (deduped.isEmpty) {
      await _storage.delete(key: key);
      return;
    }

    final encoded = jsonEncode(deduped.map((e) => e.toJson()).toList());
    await _storage.write(key: key, value: encoded);
  }

  Future<void> clearCurrentUser() async {
    final key = await _resolveCurrentKey();
    if (key == null) {
      return;
    }
    await _storage.delete(key: key);
  }

  Future<void> clearForUser(String userId) async {
    if (userId.isEmpty) {
      return;
    }
    await _storage.delete(key: _keyForUser(userId));
  }

  Future<void> clearAllUsers() async {
    final all = await _storage.readAll();
    for (final entry in all.entries) {
      if (entry.key.startsWith(_queuePrefix)) {
        await _storage.delete(key: entry.key);
      }
    }
    await _storage.delete(key: _legacyQueueKey);
  }

  Future<void> enqueue(PendingDoseLog item) async {
    if (item.occurrenceId.isEmpty) {
      return;
    }

    final queue = await _loadQueue();

    final deduped =
        queue.where((it) => it.occurrenceId != item.occurrenceId).toList()
          ..add(item);

    await _saveQueue(deduped);
  }

  Future<List<PendingDoseLog>> getPendingLogs() async {
    return _loadQueue();
  }

  Future<int> pendingCount() async {
    final queue = await _loadQueue();
    return queue.length;
  }

  Future<int> flush() async {
    final key = await _resolveCurrentKey();
    if (key == null) {
      return 0;
    }

    await _migrateLegacyIfNeeded(key);

    final queue = await _loadQueueByKey(key);
    if (queue.isEmpty) {
      return 0;
    }

    final remaining = <PendingDoseLog>[];
    var synced = 0;
    var shouldStop = false;

    for (final item in queue) {
      if (shouldStop) {
        remaining.add(item);
        continue;
      }

      try {
        await _dio.post(
          '/plans/${item.planId}/log',
          data: {
            'scheduledTime': item.scheduledTime,
            'status': item.status,
            'occurrenceId': item.occurrenceId,
            if (item.note != null && item.note!.isNotEmpty) 'note': item.note,
          },
        );
        synced += 1;
      } on DioException catch (e) {
        final issue = classifyNetworkIssue(e);
        final statusCode = e.response?.statusCode;
        final isClientError =
            statusCode != null && statusCode >= 400 && statusCode < 500;
        final isRetryableClientError = statusCode == 408 || statusCode == 429;
        final isNonRetryableClientError =
            isClientError && !isRetryableClientError;

        if (isNonRetryableClientError ||
            issue == NetworkIssueKind.unauthorized) {
          continue;
        }

        remaining.add(item);
        shouldStop =
            issue == NetworkIssueKind.noConnection ||
            issue == NetworkIssueKind.timeout ||
            issue == NetworkIssueKind.serviceUnavailable ||
            issue == NetworkIssueKind.serverError;
      } catch (_) {
        remaining.add(item);
        shouldStop = true;
      }
    }

    if (remaining.isEmpty) {
      await _storage.delete(key: key);
    } else {
      final encoded = jsonEncode(remaining.map((e) => e.toJson()).toList());
      await _storage.write(key: key, value: encoded);
    }

    return synced;
  }
}

final offlineDoseQueueProvider = Provider<OfflineDoseQueue>((ref) {
  return OfflineDoseQueue(
    ref.watch(dioProvider),
    ref.watch(currentUserStoreProvider),
  );
});
