import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/session/current_user_store.dart';
import '../domain/today_schedule.dart';

class TodayScheduleCache {
  TodayScheduleCache(this._userStore);

  static const _storage = FlutterSecureStorage();
  static const _cachePrefix = 'today_schedule_cache_v2';
  static const _legacyCacheKey = 'today_schedule_cache_v1';

  final CurrentUserStore _userStore;

  String _keyForUser(String userId) => '${_cachePrefix}_$userId';

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

    final legacy = await _storage.read(key: _legacyCacheKey);
    if (legacy == null || legacy.isEmpty) {
      return;
    }

    await _storage.write(key: scopedKey, value: legacy);
    await _storage.delete(key: _legacyCacheKey);
  }

  String _dateKey(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<TodaySchedule?> load() async {
    final key = await _resolveCurrentKey();
    if (key == null) {
      return null;
    }

    await _migrateLegacyIfNeeded(key);

    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final schedule = TodaySchedule.fromJson(json);

      final now = DateTime.now();
      final todayStr = _dateKey(now);
      if (schedule.date.startsWith(todayStr)) {
        return schedule;
      }
      return null;
    } catch (_) {
      await _storage.delete(key: key);
      return null;
    }
  }

  Future<void> save(TodaySchedule schedule) async {
    final key = await _resolveCurrentKey();
    if (key == null) {
      return;
    }

    final encoded = jsonEncode(schedule.toJson());
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
      if (entry.key.startsWith(_cachePrefix)) {
        await _storage.delete(key: entry.key);
      }
    }
    await _storage.delete(key: _legacyCacheKey);
  }
}

final todayScheduleCacheProvider = Provider<TodayScheduleCache>((ref) {
  return TodayScheduleCache(ref.watch(currentUserStoreProvider));
});
