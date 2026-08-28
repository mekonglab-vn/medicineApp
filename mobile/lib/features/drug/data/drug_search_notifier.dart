import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drug_repository.dart';

class DrugSearchState {
  const DrugSearchState({
    this.query = '',
    this.items = const [],
    this.total = 0,
    this.isLoading = false,
    this.error,
  });

  final String query;
  final List<DrugSearchItem> items;
  final int total;
  final bool isLoading;
  final String? error;

  DrugSearchState copyWith({
    String? query,
    List<DrugSearchItem>? items,
    int? total,
    bool? isLoading,
    String? error,
  }) {
    return DrugSearchState(
      query: query ?? this.query,
      items: items ?? this.items,
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class DrugSearchNotifier extends Notifier<DrugSearchState> {
  @override
  DrugSearchState build() => const DrugSearchState();

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      state = state.copyWith(
        query: trimmed,
        items: const [],
        total: 0,
        isLoading: false,
        error: null,
      );
      return;
    }

    state = state.copyWith(query: trimmed, isLoading: true, error: null);

    try {
      final repo = ref.read(drugRepositoryProvider);
      final page = await repo.search(trimmed);
      state = state.copyWith(
        items: page.items,
        total: page.total,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clear() {
    state = const DrugSearchState();
  }
}

final drugSearchNotifierProvider =
    NotifierProvider<DrugSearchNotifier, DrugSearchState>(
      DrugSearchNotifier.new,
    );
