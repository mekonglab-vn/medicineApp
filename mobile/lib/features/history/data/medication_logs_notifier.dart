import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../create_plan/data/plan_repository.dart';
import '../../create_plan/domain/medication_log.dart';

class MedicationLogsNotifier extends AsyncNotifier<MedicationLogsPage> {
  @override
  Future<MedicationLogsPage> build() async {
    final repo = ref.read(planRepositoryProvider);
    return repo.getMedicationLogs();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(planRepositoryProvider);
      return repo.getMedicationLogs();
    });
  }
}

final medicationLogsNotifierProvider =
    AsyncNotifierProvider<MedicationLogsNotifier, MedicationLogsPage>(
      MedicationLogsNotifier.new,
    );
