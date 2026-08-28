import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_error_mapper.dart';

import 'drug_interaction_repository.dart';

const lookupErrorMinDrugs = 'lookup_error_min_drugs';
const lookupErrorMinIngredients = 'lookup_error_min_ingredients';
const lookupErrorMinSingleIngredient = 'lookup_error_min_single_ingredient';

const _highAlertSeverityPriority = <String, int>{
  'contraindicated': 0,
  'major': 1,
};

class LookupInteractionState {
  const LookupInteractionState({
    this.selectedDrugNames = const [],
    this.isCheckingByDrugs = false,
    this.byDrugsResult,
    this.byDrugsError,
    this.activeIngredientQuery = '',
    this.activeIngredientSuggestions = const [],
    this.isLoadingIngredientSuggestions = false,
    this.selectedIngredients = const [],
    this.isCheckingByIngredients = false,
    this.byIngredientsResult,
    this.byIngredientsError,
    this.singleIngredientQuery = '',
    this.isCheckingSingleIngredient = false,
    this.singleIngredientResult,
    this.singleIngredientError,
  });

  final List<String> selectedDrugNames;
  final bool isCheckingByDrugs;
  final InteractionCheckResult? byDrugsResult;
  final String? byDrugsError;

  final String activeIngredientQuery;
  final List<ActiveIngredientSuggestion> activeIngredientSuggestions;
  final bool isLoadingIngredientSuggestions;
  final List<String> selectedIngredients;
  final bool isCheckingByIngredients;
  final InteractionCheckResult? byIngredientsResult;
  final String? byIngredientsError;

  final String singleIngredientQuery;
  final bool isCheckingSingleIngredient;
  final InteractionCheckResult? singleIngredientResult;
  final String? singleIngredientError;

  LookupInteractionState copyWith({
    List<String>? selectedDrugNames,
    bool? isCheckingByDrugs,
    InteractionCheckResult? byDrugsResult,
    bool clearByDrugsResult = false,
    String? byDrugsError,
    bool clearByDrugsError = false,
    String? activeIngredientQuery,
    List<ActiveIngredientSuggestion>? activeIngredientSuggestions,
    bool? isLoadingIngredientSuggestions,
    List<String>? selectedIngredients,
    bool? isCheckingByIngredients,
    InteractionCheckResult? byIngredientsResult,
    bool clearByIngredientsResult = false,
    String? byIngredientsError,
    bool clearByIngredientsError = false,
    String? singleIngredientQuery,
    bool? isCheckingSingleIngredient,
    InteractionCheckResult? singleIngredientResult,
    bool clearSingleIngredientResult = false,
    String? singleIngredientError,
    bool clearSingleIngredientError = false,
  }) {
    return LookupInteractionState(
      selectedDrugNames: selectedDrugNames ?? this.selectedDrugNames,
      isCheckingByDrugs: isCheckingByDrugs ?? this.isCheckingByDrugs,
      byDrugsResult: clearByDrugsResult
          ? null
          : byDrugsResult ?? this.byDrugsResult,
      byDrugsError: clearByDrugsError
          ? null
          : byDrugsError ?? this.byDrugsError,
      activeIngredientQuery:
          activeIngredientQuery ?? this.activeIngredientQuery,
      activeIngredientSuggestions:
          activeIngredientSuggestions ?? this.activeIngredientSuggestions,
      isLoadingIngredientSuggestions:
          isLoadingIngredientSuggestions ?? this.isLoadingIngredientSuggestions,
      selectedIngredients: selectedIngredients ?? this.selectedIngredients,
      isCheckingByIngredients:
          isCheckingByIngredients ?? this.isCheckingByIngredients,
      byIngredientsResult: clearByIngredientsResult
          ? null
          : byIngredientsResult ?? this.byIngredientsResult,
      byIngredientsError: clearByIngredientsError
          ? null
          : byIngredientsError ?? this.byIngredientsError,
      singleIngredientQuery:
          singleIngredientQuery ?? this.singleIngredientQuery,
      isCheckingSingleIngredient:
          isCheckingSingleIngredient ?? this.isCheckingSingleIngredient,
      singleIngredientResult: clearSingleIngredientResult
          ? null
          : singleIngredientResult ?? this.singleIngredientResult,
      singleIngredientError: clearSingleIngredientError
          ? null
          : singleIngredientError ?? this.singleIngredientError,
    );
  }
}

class LookupInteractionNotifier extends Notifier<LookupInteractionState> {
  @override
  LookupInteractionState build() => const LookupInteractionState();

  void addDrug(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }

    if (state.selectedDrugNames.any(
      (item) => item.toLowerCase() == trimmed.toLowerCase(),
    )) {
      return;
    }

    state = state.copyWith(
      selectedDrugNames: [...state.selectedDrugNames, trimmed],
      clearByDrugsResult: true,
      clearByDrugsError: true,
    );
  }

  void removeDrug(String name) {
    state = state.copyWith(
      selectedDrugNames: state.selectedDrugNames
          .where((item) => item != name)
          .toList(),
      clearByDrugsResult: true,
      clearByDrugsError: true,
    );
  }

  void clearDrugs() {
    state = state.copyWith(
      selectedDrugNames: const [],
      clearByDrugsResult: true,
      clearByDrugsError: true,
    );
  }

  Future<void> checkByDrugs() async {
    if (state.selectedDrugNames.length < 2) {
      state = state.copyWith(byDrugsError: lookupErrorMinDrugs);
      return;
    }

    state = state.copyWith(
      isCheckingByDrugs: true,
      clearByDrugsError: true,
      clearByDrugsResult: true,
    );

    try {
      final repo = ref.read(drugInteractionRepositoryProvider);
      final result = await repo.checkByDrugs(state.selectedDrugNames);
      state = state.copyWith(
        isCheckingByDrugs: false,
        byDrugsResult: result,
        clearByDrugsError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isCheckingByDrugs: false,
        byDrugsError: toFriendlyNetworkMessage(
          e,
          genericMessage:
              'Không thể kiểm tra tương tác thuốc. Vui lòng thử lại.',
        ),
      );
    }
  }

  Future<void> searchIngredientSuggestions(String keyword) async {
    final trimmed = keyword.trim();
    state = state.copyWith(
      activeIngredientQuery: trimmed,
      clearByIngredientsError: true,
    );

    if (trimmed.length < 2) {
      state = state.copyWith(
        activeIngredientSuggestions: const [],
        isLoadingIngredientSuggestions: false,
      );
      return;
    }

    state = state.copyWith(isLoadingIngredientSuggestions: true);

    final requestedQuery = trimmed;

    try {
      final repo = ref.read(drugInteractionRepositoryProvider);
      final suggestions = await repo.searchActiveIngredients(trimmed);

      if (state.activeIngredientQuery != requestedQuery) {
        return;
      }

      state = state.copyWith(
        activeIngredientSuggestions: suggestions,
        isLoadingIngredientSuggestions: false,
      );
    } catch (_) {
      if (state.activeIngredientQuery != requestedQuery) {
        return;
      }

      state = state.copyWith(
        isLoadingIngredientSuggestions: false,
        activeIngredientSuggestions: const [],
      );
    }
  }

  void addIngredient(String ingredient) {
    final trimmed = ingredient.trim();
    if (trimmed.isEmpty) {
      return;
    }

    if (state.selectedIngredients.any(
      (item) => item.toLowerCase() == trimmed.toLowerCase(),
    )) {
      return;
    }

    state = state.copyWith(
      selectedIngredients: [...state.selectedIngredients, trimmed],
      activeIngredientQuery: '',
      activeIngredientSuggestions: const [],
      clearByIngredientsResult: true,
      clearByIngredientsError: true,
    );
  }

  void removeIngredient(String ingredient) {
    state = state.copyWith(
      selectedIngredients: state.selectedIngredients
          .where((item) => item != ingredient)
          .toList(),
      clearByIngredientsResult: true,
      clearByIngredientsError: true,
    );
  }

  void clearIngredients() {
    state = state.copyWith(
      selectedIngredients: const [],
      activeIngredientQuery: '',
      activeIngredientSuggestions: const [],
      clearByIngredientsResult: true,
      clearByIngredientsError: true,
    );
  }

  Future<void> checkByIngredients() async {
    if (state.selectedIngredients.length < 2) {
      state = state.copyWith(byIngredientsError: lookupErrorMinIngredients);
      return;
    }

    state = state.copyWith(
      isCheckingByIngredients: true,
      clearByIngredientsError: true,
      clearByIngredientsResult: true,
    );

    try {
      final repo = ref.read(drugInteractionRepositoryProvider);
      final result = await repo.checkByActiveIngredients(
        state.selectedIngredients,
      );
      state = state.copyWith(
        isCheckingByIngredients: false,
        byIngredientsResult: result,
      );
    } catch (e) {
      state = state.copyWith(
        isCheckingByIngredients: false,
        byIngredientsError: toFriendlyNetworkMessage(
          e,
          genericMessage:
              'Không thể kiểm tra tương tác theo hoạt chất. Vui lòng thử lại.',
        ),
      );
    }
  }

  void setSingleIngredientQuery(String value) {
    final shouldClearResult =
        value.trim() != state.singleIngredientQuery.trim();
    state = state.copyWith(
      singleIngredientQuery: value,
      clearSingleIngredientError: true,
      clearSingleIngredientResult: shouldClearResult,
    );
  }

  Future<void> checkSingleIngredient() async {
    final trimmed = state.singleIngredientQuery.trim();
    if (trimmed.length < 2) {
      state = state.copyWith(
        singleIngredientError: lookupErrorMinSingleIngredient,
      );
      return;
    }

    state = state.copyWith(
      isCheckingSingleIngredient: true,
      clearSingleIngredientError: true,
      clearSingleIngredientResult: true,
    );

    try {
      final repo = ref.read(drugInteractionRepositoryProvider);
      final result = await repo.getByActiveIngredient(trimmed);
      state = state.copyWith(
        isCheckingSingleIngredient: false,
        singleIngredientResult: result,
      );
    } catch (e) {
      state = state.copyWith(
        isCheckingSingleIngredient: false,
        singleIngredientError: toFriendlyNetworkMessage(
          e,
          genericMessage:
              'Không thể tra cứu tương tác cho hoạt chất này. Vui lòng thử lại.',
        ),
      );
    }
  }
}

final lookupHighestAlertSeverityProvider = Provider<String?>((ref) {
  final state = ref.watch(lookupInteractionNotifierProvider);

  String? highest;
  int? highestRank;

  void consume(InteractionCheckResult? result) {
    if (result == null || !result.hasInteractions) {
      return;
    }

    final severity = result.highestSeverity;
    final rank = _highAlertSeverityPriority[severity];
    if (rank == null) {
      return;
    }

    if (highestRank == null || rank < highestRank!) {
      highest = severity;
      highestRank = rank;
    }
  }

  consume(state.byDrugsResult);
  consume(state.byIngredientsResult);
  consume(state.singleIngredientResult);

  return highest;
});

final lookupInteractionNotifierProvider =
    NotifierProvider<LookupInteractionNotifier, LookupInteractionState>(
      LookupInteractionNotifier.new,
    );
