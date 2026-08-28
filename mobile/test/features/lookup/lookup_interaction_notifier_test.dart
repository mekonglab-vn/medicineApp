import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/features/lookup/data/drug_interaction_repository.dart';
import 'package:medicine_app/features/lookup/data/lookup_interaction_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _FakeDrugInteractionRepository extends DrugInteractionRepository {
  _FakeDrugInteractionRepository() : super(Dio());

  InteractionCheckResult nextDrugResult = const InteractionCheckResult(
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
    interactions: [],
    groups: [],
    message: null,
  );

  InteractionCheckResult nextIngredientsResult = const InteractionCheckResult(
    hasInteractions: true,
    totalInteractions: 1,
    highestSeverity: 'contraindicated',
    severitySummary: {
      'contraindicated': 1,
      'major': 0,
      'moderate': 0,
      'minor': 0,
      'caution': 0,
      'unknown': 0,
    },
    interactions: [],
    groups: [],
    message: null,
  );

  InteractionCheckResult nextSingleIngredientResult =
      const InteractionCheckResult(
        hasInteractions: false,
        totalInteractions: 0,
        highestSeverity: 'unknown',
        severitySummary: {
          'contraindicated': 0,
          'major': 0,
          'moderate': 0,
          'minor': 0,
          'caution': 0,
          'unknown': 0,
        },
        interactions: [],
        groups: [],
        message: null,
      );

  List<ActiveIngredientSuggestion> nextSuggestions = const [
    ActiveIngredientSuggestion(name: 'Paracetamol'),
    ActiveIngredientSuggestion(name: 'Ibuprofen'),
  ];

  bool throwOnCheckByDrugs = false;

  @override
  Future<InteractionCheckResult> checkByDrugs(List<String> drugNames) async {
    if (throwOnCheckByDrugs) {
      throw Exception('forced-error');
    }

    return nextDrugResult;
  }

  @override
  Future<InteractionCheckResult> checkByActiveIngredients(
    List<String> activeIngredients,
  ) async {
    return nextIngredientsResult;
  }

  @override
  Future<InteractionCheckResult> getByActiveIngredient(
    String ingredientName,
  ) async {
    return nextSingleIngredientResult;
  }

  @override
  Future<List<ActiveIngredientSuggestion>> searchActiveIngredients(
    String keyword,
  ) async {
    return nextSuggestions;
  }
}

void main() {
  group('LookupInteractionNotifier', () {
    late _FakeDrugInteractionRepository fakeRepo;
    late ProviderContainer container;

    setUp(() {
      fakeRepo = _FakeDrugInteractionRepository();
      container = ProviderContainer(
        overrides: [
          drugInteractionRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('addDrug() de-duplicates by case-insensitive name', () {
      final notifier = container.read(
        lookupInteractionNotifierProvider.notifier,
      );

      notifier.addDrug('Paracetamol');
      notifier.addDrug('paracetamol');
      notifier.addDrug('Aspirin');

      final state = container.read(lookupInteractionNotifierProvider);
      expect(state.selectedDrugNames, ['Paracetamol', 'Aspirin']);
    });

    test(
      'checkByDrugs() returns validation key with fewer than 2 drugs',
      () async {
        final notifier = container.read(
          lookupInteractionNotifierProvider.notifier,
        );
        notifier.addDrug('Paracetamol');

        await notifier.checkByDrugs();

        final state = container.read(lookupInteractionNotifierProvider);
        expect(state.byDrugsError, lookupErrorMinDrugs);
      },
    );

    test('checkByDrugs() stores API result on success', () async {
      final notifier = container.read(
        lookupInteractionNotifierProvider.notifier,
      );
      notifier.addDrug('Paracetamol');
      notifier.addDrug('Aspirin');

      await notifier.checkByDrugs();

      final state = container.read(lookupInteractionNotifierProvider);
      expect(state.isCheckingByDrugs, false);
      expect(state.byDrugsResult?.highestSeverity, 'major');
      expect(state.byDrugsError, isNull);
    });

    test('checkByDrugs() stores friendly error on failure', () async {
      final notifier = container.read(
        lookupInteractionNotifierProvider.notifier,
      );
      notifier.addDrug('Paracetamol');
      notifier.addDrug('Aspirin');
      fakeRepo.throwOnCheckByDrugs = true;

      await notifier.checkByDrugs();

      final state = container.read(lookupInteractionNotifierProvider);
      expect(state.isCheckingByDrugs, false);
      expect(state.byDrugsError, isNotNull);
      expect(state.byDrugsResult, isNull);
    });

    test(
      'searchIngredientSuggestions() ignores keyword shorter than 2',
      () async {
        final notifier = container.read(
          lookupInteractionNotifierProvider.notifier,
        );
        await notifier.searchIngredientSuggestions('a');

        final state = container.read(lookupInteractionNotifierProvider);
        expect(state.activeIngredientSuggestions, isEmpty);
      },
    );

    test(
      'lookupHighestAlertSeverityProvider returns strongest alert',
      () async {
        final notifier = container.read(
          lookupInteractionNotifierProvider.notifier,
        );

        notifier.addDrug('Paracetamol');
        notifier.addDrug('Aspirin');
        await notifier.checkByDrugs();

        notifier.addIngredient('MAOI');
        notifier.addIngredient('Linezolid');
        await notifier.checkByIngredients();

        final highest = container.read(lookupHighestAlertSeverityProvider);
        expect(highest, 'contraindicated');
      },
    );
  });
}
