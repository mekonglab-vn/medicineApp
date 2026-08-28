import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../home/domain/today_schedule.dart';
import '../domain/medication_log.dart';
import '../domain/plan.dart';

/// Plan repository — CRUD plans via Node.js API.
class PlanRepository {
  final Dio _dio;

  PlanRepository(this._dio);

  /// Create a new grouped medication plan.
  Future<Plan> createPlan(PrescriptionPlanDraft draft) async {
    final response = await _dio.post('/plans', data: draft.toJson());
    return Plan.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  /// Get all plans for current user.
  Future<List<Plan>> getPlans({bool activeOnly = true}) async {
    final response = await _dio.get(
      '/plans',
      queryParameters: {'active': activeOnly.toString()},
    );
    // API returns: {"success": true, "data": [...plans]}
    // data is a List directly (not data.items)
    final data = response.data['data'];
    final items = data is List
        ? data
        : (data['plans'] ?? data['items'] ?? []) as List;
    return items.map((e) => Plan.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get plan by ID.
  Future<Plan> getPlanById(String id) async {
    final response = await _dio.get('/plans/$id');
    return Plan.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  /// Delete (deactivate) a plan.
  Future<void> deletePlan(String id) async {
    await _dio.delete('/plans/$id');
  }

  Future<Plan> updatePlan(String id, Plan plan) async {
    final response = await _dio.put('/plans/$id', data: plan.toUpdateJson());
    return Plan.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<Plan> setPlanActive(String id, bool isActive) async {
    final response = await _dio.put('/plans/$id', data: {'isActive': isActive});
    return Plan.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<TodaySchedule> getTodaySchedule({String? date}) async {
    final response = await _dio.get(
      '/plans/today/summary',
      queryParameters: {if (date != null && date.isNotEmpty) 'date': date},
    );
    return TodaySchedule.fromJson(
      response.data['data'] as Map<String, dynamic>,
    );
  }

  Future<void> logDose({
    required String planId,
    required String scheduledTime,
    required String status,
    required String occurrenceId,
    String? note,
  }) async {
    await _dio.post(
      '/plans/$planId/log',
      data: {
        'scheduledTime': scheduledTime,
        'status': status,
        'occurrenceId': occurrenceId,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  Future<MedicationLogsPage> getMedicationLogs({
    int page = 1,
    int limit = 20,
    String? date,
  }) async {
    final response = await _dio.get(
      '/plans/logs/all',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );

    final items = (response.data['data'] as List<dynamic>? ?? const [])
        .map((e) => MedicationLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination =
        response.data['pagination'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return MedicationLogsPage(
      items: items,
      total: pagination['total'] as int? ?? items.length,
      page: pagination['page'] as int? ?? page,
      limit: pagination['limit'] as int? ?? limit,
    );
  }
}

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return PlanRepository(ref.watch(dioProvider));
});
