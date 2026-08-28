import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/features/create_plan/data/plan_interaction_checker.dart';
import 'package:medicine_app/features/create_plan/domain/plan.dart';
import 'package:medicine_app/features/create_plan/domain/scan_result.dart';
import 'package:medicine_app/features/lookup/data/drug_interaction_repository.dart';

class _FakeDrugInteractionRepository extends DrugInteractionRepository {
  _FakeDrugInteractionRepository() : super(Dio());

  InteractionCheckResult nextResult = const InteractionCheckResult(
    hasInteractions: true,
    totalInteractions: 1,
    highestSeverity: 'major',
    severitySummary: {
      'contraindicated': 0,
      'major': 1,
      'moderate': 0,
      'minor': 0,
      'caution': 0,
      'unknown': 0,
    },
    interactions: [
      InteractionItem(
        drugA: 'Paracetamol',
        drugB: 'Warfarin',
        ingredientA: 'Paracetamol',
        ingredientB: 'Warfarin',
        severity: 'major',
        severityOriginal: 'Nghiem trong',
        warning: 'Tang nguy co chay mau',
      ),
    ],
    groups: [],
    message: null,
  );

  List<String> lastInput = const [];

  @override
  Future<InteractionCheckResult> checkByDrugs(List<String> drugNames) async {
    lastInput = List<String>.from(drugNames);
    return nextResult;
  }
}

void main() {
  group('PlanInteractionChecker', () {
    late _FakeDrugInteractionRepository fakeRepo;
    late PlanInteractionChecker checker;

    setUp(() {
      fakeRepo = _FakeDrugInteractionRepository();
      checker = PlanInteractionChecker(fakeRepo);
    });

    test('deduplicates requested drug names before API call', () async {
      await checker.checkDetectedDrugs([
        const DetectedDrug(name: 'Paracetamol', mappedDrugName: 'Paracetamol'),
        const DetectedDrug(name: 'paracetamol', mappedDrugName: 'Paracetamol'),
        const DetectedDrug(name: 'Warfarin', mappedDrugName: 'Warfarin'),
      ]);

      expect(fakeRepo.lastInput, ['Paracetamol', 'Warfarin']);
    });

    test('maps interaction severity to matched detected drugs', () async {
      final summary = await checker.checkDetectedDrugs([
        const DetectedDrug(
          name: 'Paracetamol 500mg',
          mappedDrugName: 'Paracetamol',
        ),
        const DetectedDrug(name: 'Warfarin', mappedDrugName: 'Warfarin'),
      ]);

      expect(summary.hasInteractions, true);
      expect(summary.highestSeverity, 'major');
      expect(summary.severityForDrugName('Paracetamol 500mg'), 'major');
      expect(summary.severityForDrugName('Warfarin'), 'major');
    });

    test('returns empty summary when less than 2 unique drugs', () async {
      final summary = await checker.checkPlanDrugs([
        PlanDrugItem(name: 'Paracetamol'),
      ]);

      expect(summary.requestedDrugNames, ['Paracetamol']);
      expect(summary.hasInteractions, false);
      expect(fakeRepo.lastInput, isEmpty);
    });

    test('maps ingredient fallback names when drug names missing', () async {
      fakeRepo.nextResult = const InteractionCheckResult(
        hasInteractions: true,
        totalInteractions: 1,
        highestSeverity: 'moderate',
        severitySummary: {
          'contraindicated': 0,
          'major': 0,
          'moderate': 1,
          'minor': 0,
          'caution': 0,
          'unknown': 0,
        },
        interactions: [
          InteractionItem(
            drugA: '',
            drugB: '',
            ingredientA: 'Losartan',
            ingredientB: 'Ibuprofen',
            severity: 'moderate',
            severityOriginal: 'Trung binh',
            warning: 'Can theo doi huyet ap',
          ),
        ],
        groups: [],
        message: null,
      );

      final summary = await checker.checkDetectedDrugs([
        const DetectedDrug(name: 'Losartan STADA', ocrText: 'Losartan'),
        const DetectedDrug(name: 'Ibuprofen 400mg', ocrText: 'Ibuprofen'),
      ]);

      expect(summary.severityForDrugName('Losartan STADA'), 'moderate');
      expect(summary.severityForDrugName('Ibuprofen 400mg'), 'moderate');
    });
  });
}
