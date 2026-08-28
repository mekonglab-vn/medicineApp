import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../drug/data/drug_repository.dart';
import '../../domain/plan.dart';

class DrugEntrySheet extends StatefulWidget {
  const DrugEntrySheet({super.key, required this.ref, this.initial});

  final WidgetRef ref;
  final PlanDrugItem? initial;

  @override
  State<DrugEntrySheet> createState() => _DrugEntrySheetState();
}

class _DrugEntrySheetState extends State<DrugEntrySheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _dosageCtrl;
  late final TextEditingController _pillsCtrl;
  late final TextEditingController _daysCtrl;
  Timer? _debounceTimer;

  List<DrugSearchItem> _suggestions = [];
  bool _loadingSuggestions = false;
  // Tracks last query that produced the current suggestion set — used to
  // avoid clearing the list when the user selects an item and the controller
  // fires a change event with the newly‑selected name.
  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial?.name ?? '');
    _dosageCtrl = TextEditingController(text: widget.initial?.dosage ?? '');
    _pillsCtrl = TextEditingController(
      text: (widget.initial?.pillsPerDose ?? 1).toString(),
    );
    _daysCtrl = TextEditingController(
      text: (widget.initial?.totalDays ?? 7).toString(),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _pillsCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Search with debounce
  // ---------------------------------------------------------------------------

  void _onNameChanged(String query) {
    final trimmed = query.trim();

    // Reset suggestions immediately when query is too short — no debounce needed.
    if (trimmed.length < 2) {
      _debounceTimer?.cancel();
      if (mounted) {
        setState(() {
          _suggestions = [];
          _loadingSuggestions = false;
          _lastSearchQuery = '';
        });
      }
      return;
    }

    // Avoid re-searching when user just selected a suggestion (name matches).
    if (trimmed == _lastSearchQuery) return;

    // Show loading immediately so the layout area is stable before results arrive.
    if (!_loadingSuggestions && mounted) {
      setState(() => _loadingSuggestions = true);
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 380), () {
      _fetchSuggestions(trimmed);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    try {
      final repo = widget.ref.read(drugRepositoryProvider);
      final page = await repo.search(query, limit: 6);
      if (mounted) {
        setState(() {
          _suggestions = page.items;
          _loadingSuggestions = false;
          _lastSearchQuery = query;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _loadingSuggestions = false;
        });
      }
    }
  }

  void _selectSuggestion(DrugSearchItem item) {
    _debounceTimer?.cancel();
    setState(() {
      _nameCtrl.text = item.name;
      // Mark so that the onChange from setText doesn't trigger a new search.
      _lastSearchQuery = item.name.trim();
      _suggestions = [];
      _loadingSuggestions = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final pillsValue = int.tryParse(_pillsCtrl.text) ?? 1;
    final daysValue = int.tryParse(_daysCtrl.text) ?? 7;

    final initial = widget.initial;
    Navigator.pop(
      context,
      PlanDrugItem(
        name: name,
        dosage: _dosageCtrl.text.trim(),
        pillsPerDose: pillsValue < 1 ? 1 : pillsValue,
        frequency: initial?.frequency ?? 'daily',
        times: initial?.times,
        totalDays: daysValue < 1 ? 1 : daysValue,
        notes: initial?.notes ?? '',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              widget.initial == null
                  ? l10n.drugEntrySheetAddTitle
                  : l10n.drugEntrySheetEditTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),

            // Drug name field
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              onChanged: _onNameChanged,
              decoration: InputDecoration(
                labelText: l10n.drugEntrySheetNameLabel,
                hintText: l10n.drugEntrySheetNameHint,
                prefixIcon: const Icon(Icons.medication_outlined),
              ),
            ),

            // ── Suggestion zone ──────────────────────────────────────────────
            // AnimatedSize keeps the zone height stable while content changes,
            // preventing the layout from jumping when suggestions appear/vanish.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _buildSuggestionZone(l10n),
            ),

            const SizedBox(height: 12),

            // Dosage field
            TextField(
              controller: _dosageCtrl,
              decoration: InputDecoration(
                labelText: l10n.drugEntrySheetDosageLabel,
                hintText: l10n.drugEntrySheetDosageHint,
                prefixIcon: const Icon(Icons.scale_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // Pills/Dose and Total Days Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pillsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.drugEntrySheetPillsPerDoseLabel,
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _daysCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.drugEntrySheetTotalDaysLabel,
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.drugEntrySheetCancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: Text(
                      widget.initial == null
                          ? l10n.drugEntrySheetAdd
                          : l10n.drugEntrySheetSave,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Suggestion zone widget
  // ---------------------------------------------------------------------------

  Widget _buildSuggestionZone(AppLocalizations l10n) {
    // Nothing to show — return zero-size widget so AnimatedSize collapses.
    if (!_loadingSuggestions && _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
      ),
      child: _loadingSuggestions && _suggestions.isEmpty
          ? _SuggestionLoadingRow(label: l10n.drugEntrySheetSearching)
          : ListView.separated(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = _suggestions[i];
                return ListTile(
                  dense: true,
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: item.activeIngredient != null
                      ? Text(
                          item.activeIngredient!,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: const Icon(
                    Icons.north_west,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  onTap: () => _selectSuggestion(item),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact loading row inside the suggestion zone
// ---------------------------------------------------------------------------

class _SuggestionLoadingRow extends StatelessWidget {
  const _SuggestionLoadingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Row(
        children: [
          const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
