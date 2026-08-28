import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../drug/data/drug_repository.dart';
import '../../drug/data/drug_search_notifier.dart';
import '../data/drug_interaction_repository.dart';
import '../data/lookup_interaction_notifier.dart';

enum LookupSection { drugs, interactions, ingredients }

class LookupScreen extends StatefulWidget {
  const LookupScreen({super.key});

  @override
  State<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends State<LookupScreen> {
  LookupSection _section = LookupSection.drugs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.lookupTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: SegmentedButton<LookupSection>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment<LookupSection>(
                  value: LookupSection.drugs,
                  icon: const Icon(Icons.medication_outlined),
                  label: Text(l10n.lookupSectionDrugs),
                ),
                ButtonSegment<LookupSection>(
                  value: LookupSection.interactions,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text(l10n.lookupSectionInteractions),
                ),
                ButtonSegment<LookupSection>(
                  value: LookupSection.ingredients,
                  icon: const Icon(Icons.science_outlined),
                  label: Text(l10n.lookupSectionIngredients),
                ),
              ],
              selected: {_section},
              onSelectionChanged: (selected) {
                setState(() {
                  _section = selected.first;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: switch (_section) {
              LookupSection.drugs => const _DrugLookupSection(),
              LookupSection.interactions => const _DrugInteractionsSection(),
              LookupSection.ingredients => const _ActiveIngredientSection(),
            },
          ),
        ],
      ),
    );
  }
}

class _DrugLookupSection extends ConsumerStatefulWidget {
  const _DrugLookupSection();

  @override
  ConsumerState<_DrugLookupSection> createState() => _DrugLookupSectionState();
}

class _DrugLookupSectionState extends ConsumerState<_DrugLookupSection> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) {
        return;
      }
      ref.read(drugSearchNotifierProvider.notifier).search(value);
    });
  }

  Future<void> _openDetails(DrugSearchItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    try {
      final repo = ref.read(drugRepositoryProvider);
      final details = await repo.getByName(item.name);
      if (!mounted) {
        return;
      }

      context.push(
        '/drugs/detail',
        extra: {'details': details, 'activeIngredient': item.activeIngredient},
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            toFriendlyNetworkMessage(
              e,
              genericMessage: l10n.lookupErrorLoadDrugDetail,
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(drugSearchNotifierProvider);
    final l10n = AppLocalizations.of(context);

    return Container(
      key: const ValueKey('lookup-drugs'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.lookupDrugSectionTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.lookupDrugSectionSubtitle,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: l10n.lookupDrugSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () {
                  _controller.clear();
                  ref.read(drugSearchNotifierProvider.notifier).clear();
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.error != null)
            _InlineError(
              message: toFriendlyNetworkMessage(
                state.error!,
                genericMessage: l10n.lookupErrorSearchDrugs,
              ),
            )
          else if (state.query.trim().length < 2)
            _InlineHint(
              icon: Icons.search_rounded,
              message: l10n.lookupHintEnterAtLeast2Chars,
            )
          else if (state.items.isEmpty)
            _InlineHint(
              icon: Icons.info_outline,
              message: l10n.lookupHintNoDrugResult,
            )
          else
            Column(
              children: [
                for (final item in state.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => _openDetails(item),
                      borderRadius: BorderRadius.circular(16),
                      child: Ink(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSoft,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.14,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.medication_outlined,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.activeIngredient?.trim().isNotEmpty ==
                                            true
                                        ? item.activeIngredient!
                                        : l10n.lookupUnknownIngredient,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                item.score.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DrugInteractionsSection extends ConsumerStatefulWidget {
  const _DrugInteractionsSection();

  @override
  ConsumerState<_DrugInteractionsSection> createState() =>
      _DrugInteractionsSectionState();
}

class _DrugInteractionsSectionState
    extends ConsumerState<_DrugInteractionsSection> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _debouncedKeyword = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _debouncedKeyword = value.trim();
      });
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() {
      _debouncedKeyword = '';
    });
  }

  void _addDrug(String name) {
    ref.read(lookupInteractionNotifierProvider.notifier).addDrug(name);
    _clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(lookupInteractionNotifierProvider);
    final suggestionsAsync = ref.watch(
      lookupDrugSuggestionsProvider(_debouncedKeyword),
    );
    final hasSuggestionQuery = _debouncedKeyword.length >= 2;

    return Container(
      key: const ValueKey('lookup-interactions'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.lookupInteractionSectionTitle,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.lookupInteractionSectionSubtitle,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: l10n.lookupInteractionDrugSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () {
                  _clearSearch();
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          if (hasSuggestionQuery && suggestionsAsync.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (hasSuggestionQuery)
            suggestionsAsync.when(
              data: (suggestions) {
                if (suggestions.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _SuggestionList(
                    suggestions: suggestions,
                    unknownIngredientLabel: l10n.lookupUnknownIngredient,
                    onTap: (item) => _addDrug(item.name),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _InlineError(
                  message: toFriendlyNetworkMessage(
                    error,
                    genericMessage: l10n.lookupErrorSearchDrugs,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _SelectedChips(
            values: state.selectedDrugNames,
            emptyMessage: l10n.lookupHintNoSelectedDrugs,
            onRemove: (value) {
              ref
                  .read(lookupInteractionNotifierProvider.notifier)
                  .removeDrug(value);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: state.isCheckingByDrugs
                      ? null
                      : () => ref
                            .read(lookupInteractionNotifierProvider.notifier)
                            .checkByDrugs(),
                  icon: const Icon(Icons.shield_outlined),
                  label: Text(l10n.lookupActionCheckInteractions),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 132,
                child: OutlinedButton(
                  onPressed: state.selectedDrugNames.isEmpty
                      ? null
                      : () => ref
                            .read(lookupInteractionNotifierProvider.notifier)
                            .clearDrugs(),
                  child: Text(l10n.lookupActionClearSelection),
                ),
              ),
            ],
          ),
          if (state.isCheckingByDrugs)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (state.byDrugsError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _InlineError(
                message: _resolveLookupErrorMessage(
                  context,
                  state.byDrugsError!,
                ),
              ),
            ),
          if (state.byDrugsResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _InteractionResultView(
                title: l10n.lookupResultByDrugsTitle,
                result: state.byDrugsResult!,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveIngredientSection extends ConsumerStatefulWidget {
  const _ActiveIngredientSection();

  @override
  ConsumerState<_ActiveIngredientSection> createState() =>
      _ActiveIngredientSectionState();
}

class _ActiveIngredientSectionState
    extends ConsumerState<_ActiveIngredientSection> {
  final TextEditingController _ingredientController = TextEditingController();
  final TextEditingController _singleIngredientController =
      TextEditingController();

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ingredientController.dispose();
    _singleIngredientController.dispose();
    super.dispose();
  }

  void _onIngredientChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) {
        return;
      }
      ref
          .read(lookupInteractionNotifierProvider.notifier)
          .searchIngredientSuggestions(value);
    });
  }

  void _addIngredient(String ingredient) {
    ref
        .read(lookupInteractionNotifierProvider.notifier)
        .addIngredient(ingredient);
    _ingredientController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(lookupInteractionNotifierProvider);

    return Column(
      key: const ValueKey('lookup-ingredients'),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.lookupIngredientsSectionTitle,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.lookupIngredientsSectionSubtitle,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ingredientController,
                onChanged: _onIngredientChanged,
                decoration: InputDecoration(
                  hintText: l10n.lookupIngredientSearchHint,
                  prefixIcon: const Icon(Icons.science_outlined),
                  suffixIcon: IconButton(
                    onPressed: () {
                      _ingredientController.clear();
                      _onIngredientChanged('');
                    },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
              if (state.isLoadingIngredientSuggestions)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (state.activeIngredientSuggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                _IngredientSuggestionList(
                  suggestions: state.activeIngredientSuggestions,
                  onTap: (item) => _addIngredient(item.name),
                ),
              ],
              const SizedBox(height: 12),
              _SelectedChips(
                values: state.selectedIngredients,
                emptyMessage: l10n.lookupHintNoSelectedIngredients,
                onRemove: (value) => ref
                    .read(lookupInteractionNotifierProvider.notifier)
                    .removeIngredient(value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: state.isCheckingByIngredients
                          ? null
                          : () => ref
                                .read(
                                  lookupInteractionNotifierProvider.notifier,
                                )
                                .checkByIngredients(),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(l10n.lookupActionCheckByIngredients),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 132,
                    child: OutlinedButton(
                      onPressed: state.selectedIngredients.isEmpty
                          ? null
                          : () => ref
                                .read(
                                  lookupInteractionNotifierProvider.notifier,
                                )
                                .clearIngredients(),
                      child: Text(l10n.lookupActionClearSelection),
                    ),
                  ),
                ],
              ),
              if (state.isCheckingByIngredients)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (state.byIngredientsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InlineError(
                    message: _resolveLookupErrorMessage(
                      context,
                      state.byIngredientsError!,
                    ),
                  ),
                ),
              if (state.byIngredientsResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _InteractionResultView(
                    title: l10n.lookupResultByIngredientsTitle,
                    result: state.byIngredientsResult!,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.lookupSingleIngredientTitle,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.lookupSingleIngredientSubtitle,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.push('/lookup/ingredients'),
                  icon: const Icon(Icons.format_list_bulleted_rounded),
                  label: const Text('Danh mục hoạt chất'),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _singleIngredientController,
                onChanged: (value) => ref
                    .read(lookupInteractionNotifierProvider.notifier)
                    .setSingleIngredientQuery(value),
                decoration: InputDecoration(
                  hintText: l10n.lookupSingleIngredientHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: state.isCheckingSingleIngredient
                          ? null
                          : () => ref
                                .read(
                                  lookupInteractionNotifierProvider.notifier,
                                )
                                .checkSingleIngredient(),
                      icon: const Icon(Icons.travel_explore_outlined),
                      label: Text(l10n.lookupActionLookupIngredient),
                    ),
                  ),
                ],
              ),
              if (state.isCheckingSingleIngredient)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (state.singleIngredientError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InlineError(
                    message: _resolveLookupErrorMessage(
                      context,
                      state.singleIngredientError!,
                    ),
                  ),
                ),
              if (state.singleIngredientResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _InteractionResultView(
                    title: l10n.lookupResultBySingleIngredientTitle,
                    result: state.singleIngredientResult!,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.suggestions,
    required this.unknownIngredientLabel,
    required this.onTap,
  });

  final List<DrugSearchItem> suggestions;
  final String unknownIngredientLabel;
  final ValueChanged<DrugSearchItem> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = suggestions[index];
          return ListTile(
            dense: true,
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item.activeIngredient?.trim().isNotEmpty == true
                  ? item.activeIngredient!
                  : unknownIngredientLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () => onTap(item),
          );
        },
      ),
    );
  }
}

class _IngredientSuggestionList extends StatelessWidget {
  const _IngredientSuggestionList({
    required this.suggestions,
    required this.onTap,
  });

  final List<ActiveIngredientSuggestion> suggestions;
  final ValueChanged<ActiveIngredientSuggestion> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = suggestions[index];
          return ListTile(
            dense: true,
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              l10n.lookupIngredientSuggestionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () => onTap(item),
          );
        },
      ),
    );
  }
}

class _SelectedChips extends StatelessWidget {
  const _SelectedChips({
    required this.values,
    required this.emptyMessage,
    required this.onRemove,
  });

  final List<String> values;
  final String emptyMessage;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return _InlineHint(icon: Icons.inbox_outlined, message: emptyMessage);
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => Chip(
              label: Text(value),
              onDeleted: () => onRemove(value),
              deleteIcon: const Icon(Icons.close, size: 18),
            ),
          )
          .toList(),
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractionResultView extends StatelessWidget {
  const _InteractionResultView({required this.title, required this.result});

  final String title;
  final InteractionCheckResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = result.interactions;
    final groups = result.groups;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SeverityBadge(
                label: _severityLabel(context, result.highestSeverity),
                severity: result.highestSeverity,
              ),
              Chip(
                label: Text(l10n.lookupSummaryTotal(result.totalInteractions)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SeveritySummaryRow(summary: result.severitySummary),
          const SizedBox(height: 10),
          if (!result.hasInteractions)
            _InlineHint(
              icon: Icons.verified_user_outlined,
              message: l10n.lookupNoInteractions,
            )
          else if (groups.isNotEmpty)
            Column(
              children: [
                for (final group in groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InteractionGroupCard(group: group),
                  ),
              ],
            )
          else
            Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InteractionItemTile(item: item),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SeveritySummaryRow extends StatelessWidget {
  const _SeveritySummaryRow({required this.summary});

  final Map<String, int> summary;

  @override
  Widget build(BuildContext context) {
    const order = [
      'contraindicated',
      'major',
      'moderate',
      'minor',
      'caution',
      'unknown',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in order)
          if ((summary[key] ?? 0) > 0)
            _SeverityBadge(
              label: '${_severityLabel(context, key)}: ${summary[key]}',
              severity: key,
            ),
      ],
    );
  }
}

class _InteractionGroupCard extends StatelessWidget {
  const _InteractionGroupCard({required this.group});

  final InteractionGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SeverityBadge(
                label: _severityLabel(context, group.severity),
                severity: group.severity,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).lookupGroupPairCount(group.count),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in group.interactions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _InteractionItemTile(item: item),
            ),
        ],
      ),
    );
  }
}

class _InteractionItemTile extends StatelessWidget {
  const _InteractionItemTile({required this.item});

  final InteractionItem item;

  @override
  Widget build(BuildContext context) {
    final pairText = _pairText(context, item);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pairText,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              _SeverityBadge(
                label: _severityLabel(context, item.severity),
                severity: item.severity,
              ),
            ],
          ),
          if (item.warning.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.warning,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _pairText(BuildContext context, InteractionItem item) {
    final first = item.drugA.trim().isNotEmpty
        ? item.drugA.trim()
        : item.ingredientA.trim();
    final second = item.drugB.trim().isNotEmpty
        ? item.drugB.trim()
        : item.ingredientB.trim();

    if (first.isEmpty && second.isEmpty) {
      return AppLocalizations.of(context).lookupUnknownInteractionPair;
    }

    if (second.isEmpty) {
      return first;
    }

    return '$first + $second';
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.label, required this.severity});

  final String label;
  final String severity;

  @override
  Widget build(BuildContext context) {
    final palette = _severityPalette(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.foreground,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SeverityPalette {
  const _SeverityPalette({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

_SeverityPalette _severityPalette(String severity) {
  switch (severity) {
    case 'contraindicated':
      return const _SeverityPalette(
        background: AppColors.severityCriticalBg,
        foreground: AppColors.severityCriticalFg,
      );
    case 'major':
      return const _SeverityPalette(
        background: AppColors.severityHighBg,
        foreground: AppColors.severityHighFg,
      );
    case 'moderate':
      return const _SeverityPalette(
        background: AppColors.severityModerateBg,
        foreground: AppColors.severityModerateFg,
      );
    case 'minor':
      return const _SeverityPalette(
        background: AppColors.severityLowBg,
        foreground: AppColors.severityLowFg,
      );
    case 'caution':
      return const _SeverityPalette(
        background: AppColors.severityInfoBg,
        foreground: AppColors.severityInfoFg,
      );
    default:
      return const _SeverityPalette(
        background: AppColors.surfaceSoft,
        foreground: AppColors.textSecondary,
      );
  }
}

String _severityLabel(BuildContext context, String severity) {
  final l10n = AppLocalizations.of(context);

  switch (severity) {
    case 'contraindicated':
      return l10n.lookupSeverityContraindicated;
    case 'major':
      return l10n.lookupSeverityMajor;
    case 'moderate':
      return l10n.lookupSeverityModerate;
    case 'minor':
      return l10n.lookupSeverityMinor;
    case 'caution':
      return l10n.lookupSeverityCaution;
    default:
      return l10n.lookupSeverityUnknown;
  }
}

String _resolveLookupErrorMessage(BuildContext context, String error) {
  final l10n = AppLocalizations.of(context);

  switch (error) {
    case lookupErrorMinDrugs:
      return l10n.lookupErrorMinDrugs;
    case lookupErrorMinIngredients:
      return l10n.lookupErrorMinIngredients;
    case lookupErrorMinSingleIngredient:
      return l10n.lookupErrorMinSingleIngredient;
    default:
      return error;
  }
}
