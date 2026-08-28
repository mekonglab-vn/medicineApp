import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../create_plan/domain/plan.dart';

class PlanCache {
  static const _storage = FlutterSecureStorage();
  static const _cachePrefix = 'plans_cache_v1';

  String _keyFor({required String userId, required bool activeOnly}) {
    final suffix = activeOnly ? 'active' : 'all';
    return '${_cachePrefix}_${userId}_$suffix';
  }

  Future<List<Plan>> load({
    required String userId,
    required bool activeOnly,
  }) async {
    final raw = await _storage.read(
      key: _keyFor(userId: userId, activeOnly: activeOnly),
    );
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final parsed = jsonDecode(raw) as List<dynamic>;
      return parsed
          .map((entry) => Plan.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      await _storage.delete(
        key: _keyFor(userId: userId, activeOnly: activeOnly),
      );
      return const [];
    }
  }

  Future<void> save({
    required String userId,
    required bool activeOnly,
    required List<Plan> plans,
  }) async {
    final encoded = jsonEncode(
      plans
          .map(
            (plan) => {
              'id': plan.id,
              'title': plan.title,
              'drugs': plan.drugs.map((item) => item.toJson()).toList(),
              'slots': plan.slots.map((slot) => slot.toJson()).toList(),
              if (plan.totalDays != null) 'total_days': plan.totalDays,
              'start_date': plan.startDate,
              if (plan.endDate != null) 'end_date': plan.endDate,
              'is_active': plan.isActive,
              if (plan.notes != null) 'notes': plan.notes,
            },
          )
          .toList(),
    );

    await _storage.write(
      key: _keyFor(userId: userId, activeOnly: activeOnly),
      value: encoded,
    );
  }

  Future<void> clearForUser(String userId) async {
    await _storage.delete(key: _keyFor(userId: userId, activeOnly: true));
    await _storage.delete(key: _keyFor(userId: userId, activeOnly: false));
  }

  Future<void> clearAllUsers() async {
    final all = await _storage.readAll();
    for (final entry in all.entries) {
      if (entry.key.startsWith(_cachePrefix)) {
        await _storage.delete(key: entry.key);
      }
    }
  }
}

final planCacheProvider = Provider<PlanCache>((ref) {
  return PlanCache();
});
