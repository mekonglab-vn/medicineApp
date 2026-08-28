import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/step_wizard_progress.dart';
import '../../lookup/data/drug_interaction_repository.dart';
import '../data/plan_interaction_checker.dart';
import '../domain/plan.dart';
import '../domain/scan_result.dart';
import 'widgets/drug_entry_sheet.dart';

class ScanReviewScreen extends ConsumerStatefulWidget {
  const ScanReviewScreen({super.key, required this.result});

  final ScanResult result;

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  late List<DetectedDrug> _drugs;
  final _searchCtrl = TextEditingController();
  PlanInteractionSummary _interactionSummary = PlanInteractionSummary.empty();
  bool _isCheckingInteractions = false;
  String? _interactionError;
  int _interactionRequestId = 0;

  @override
  void initState() {
    super.initState();
    _drugs = List<DetectedDrug>.from(widget.result.drugs);
    _refreshInteractionSummary();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DetectedDrug> get _visibleDrugs {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _drugs.where((drug) {
      final haystack = '${drug.name} ${drug.ocrText}'.toLowerCase();
      return q.isEmpty || haystack.contains(q);
    }).toList()..sort((a, b) {
      if (a.needsReview && !b.needsReview) return -1;
      if (!a.needsReview && b.needsReview) return 1;
      return 0;
    });
  }

  void _removeDrug(DetectedDrug drug) {
    setState(() => _drugs.remove(drug));
    _refreshInteractionSummary();
  }

  Future<void> _editDrug(DetectedDrug drug) async {
    final current = drug;
    final initial = PlanDrugItem(
      name: current.name,
      dosage: current.dosage ?? '',
    );

    final result = await showModalBottomSheet<PlanDrugItem?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DrugEntrySheet(ref: ref, initial: initial),
    );

    if (result != null) {
      final index = _drugs.indexOf(current);
      if (index >= 0) {
        setState(() {
          _drugs[index] = DetectedDrug(
            name: result.name,
            dosage: result.dosage,
            confidence: current.confidence,
            matchScore: current.matchScore,
            mappingStatus: 'confirmed',
            ocrText: current.ocrText,
            mappedDrugName: result.name,
            frequency: current.frequency,
            sources: current.sources,
          );
        });
        _refreshInteractionSummary();
      }
    }
  }

  Future<void> _addDrugManually() async {
    final result = await showModalBottomSheet<PlanDrugItem?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DrugEntrySheet(ref: ref),
    );

    if (result != null) {
      setState(() {
        _drugs.add(
          DetectedDrug(
            name: result.name,
            dosage: result.dosage,
            mappingStatus: 'confirmed',
            confidence: 1.0,
          ),
        );
      });
      _refreshInteractionSummary();
    }
  }

  Future<void> _continue() async {
    if (_interactionSummary.hasInteractions) {
      final proceed = await _showInteractionConfirmDialog();
      if (!proceed) {
        return;
      }
    }

    final items = _drugs.map((d) {
      final freqCount = d.frequency > 0 ? d.frequency : 1;
      List<String> autoTimes;
      String freqKey;

      if (freqCount == 2) {
        autoTimes = ['08:00', '18:00'];
        freqKey = '2_times_daily';
      } else if (freqCount == 3) {
        autoTimes = ['08:00', '12:00', '18:00'];
        freqKey = '3_times_daily';
      } else if (freqCount >= 4) {
        autoTimes = ['07:00', '11:00', '16:00', '20:00'];
        freqKey = '4_times_daily';
      } else {
        autoTimes = ['08:00'];
        freqKey = 'daily';
      }

      // Parse detailed dose schedule per session (Sáng Xv, Trưa Yv, Tối Zv, Chiều Wv)
      final rawText = d.ocrText.toLowerCase();
      List<DoseScheduleItem>? parsedDoseSchedule;
      final scheduleMatches = <DoseScheduleItem>[];

      int parsePillsFromMatch(String fullText, String keyword) {
        final pattern = RegExp(
          keyword + r'\s*[:\-\=\s]*\s*(\d+|i|l)\b',
          caseSensitive: false,
        );
        final match = pattern.firstMatch(fullText);
        if (match == null) return 1;
        final val = match.group(1)!;
        if (val.toLowerCase() == 'i' || val.toLowerCase() == 'l') return 1;
        return int.tryParse(val) ?? 1;
      }

      final hasSang = RegExp(r'sáng|sang', caseSensitive: false).hasMatch(rawText);
      final hasTrua = RegExp(r'trưa|trua', caseSensitive: false).hasMatch(rawText);
      final hasChieu = RegExp(r'chiều|chieu|tối|toi', caseSensitive: false).hasMatch(rawText);

      if (hasSang) {
        final pills = parsePillsFromMatch(rawText, r'(?:sáng|sang)');
        scheduleMatches.add(DoseScheduleItem(time: '08:00', pills: pills));
      }
      if (hasTrua) {
        final pills = parsePillsFromMatch(rawText, r'(?:trưa|trua)');
        scheduleMatches.add(DoseScheduleItem(time: '12:00', pills: pills));
      }
      if (hasChieu) {
        final pills = parsePillsFromMatch(rawText, r'(?:chiều|chieu|tối|toi)');
        scheduleMatches.add(DoseScheduleItem(time: '18:00', pills: pills));
      }

      if (scheduleMatches.isNotEmpty) {
        parsedDoseSchedule = scheduleMatches;
      }

      // Extract instruction notes (nhai nát, trước/sau ăn 30p, v.v.)
      final noteParts = <String>[];
      if (rawText.contains('nhai nát') || rawText.contains('nhai nat') || rawText.contains('nhại nát')) {
        noteParts.add('Nhai nát trước khi uống');
      }
      if (rawText.contains('trước ăn') || rawText.contains('truoc an')) {
        noteParts.add('Uống trước khi ăn 30 phút');
      } else if (rawText.contains('sau ăn') || rawText.contains('sau an')) {
        noteParts.add('Uống sau khi ăn 30 phút');
      }

      if (scheduleMatches.isNotEmpty) {
        final detail = scheduleMatches.map((m) {
          final session = m.time == '08:00' ? 'Sáng' : (m.time == '12:00' ? 'Trưa' : 'Tối');
          return '$session ${m.pills}v';
        }).join(' · ');
        noteParts.add(detail);
      }

      final notes = noteParts.join(' · ');

      return PlanDrugItem(
        name: d.mappedDrugName ?? d.name,
        dosage: d.dosage ?? '',
        frequency: freqKey,
        times: parsedDoseSchedule != null ? parsedDoseSchedule.map((e) => e.time).toList() : autoTimes,
        doseSchedule: parsedDoseSchedule,
        pillsPerDose: parsedDoseSchedule != null && parsedDoseSchedule.isNotEmpty ? parsedDoseSchedule.first.pills : 1,
        notes: notes,
      );
    }).toList();

    if (!mounted) {
      return;
    }
    // Skip edit_drugs step — go directly to schedule
    context.go('/create/schedule', extra: items);
  }

  Future<void> _refreshInteractionSummary() async {
    final requestId = ++_interactionRequestId;
    setState(() {
      _isCheckingInteractions = true;
      _interactionError = null;
    });

    try {
      final checker = ref.read(planInteractionCheckerProvider);
      final summary = await checker.checkDetectedDrugs(_drugs);
      if (!mounted || requestId != _interactionRequestId) {
        return;
      }
      setState(() {
        _interactionSummary = summary;
        _isCheckingInteractions = false;
      });
    } catch (e) {
      if (!mounted || requestId != _interactionRequestId) {
        return;
      }
      setState(() {
        _isCheckingInteractions = false;
        _interactionError = toFriendlyNetworkMessage(
          e,
          genericMessage:
              'Không thể kiểm tra tương tác thuốc lúc này. Vui lòng thử lại.',
        );
      });
    }
  }

  String? _severityForDrug(DetectedDrug drug) {
    return _interactionSummary.severityForDrugName(drug.name);
  }

  Future<bool> _showInteractionConfirmDialog() async {
    final l10n = AppLocalizations.of(context);
    final severity = _severityLabel(l10n, _interactionSummary.highestSeverity);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận tiếp tục dù có tương tác?'),
        content: Text(
          'Phát hiện ${_interactionSummary.totalInteractions} cặp tương tác '
          '(mức cao nhất: $severity). '
          'Bạn nên kiểm tra lại danh sách thuốc trước khi lập lịch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Vẫn tiếp tục lập lịch'),
          ),
        ],
      ),
    );

    return result == true;
  }

  String _severityLabel(AppLocalizations l10n, String severity) {
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

  String _interactionPairLabel(InteractionItem item) {
    final first = item.drugA.trim().isNotEmpty
        ? item.drugA.trim()
        : item.ingredientA.trim();
    final second = item.drugB.trim().isNotEmpty
        ? item.drugB.trim()
        : item.ingredientB.trim();

    if (first.isEmpty && second.isEmpty) {
      return 'Cặp chưa xác định';
    }
    if (second.isEmpty) {
      return first;
    }
    return '$first + $second';
  }

  Widget _buildInteractionPanel(AppLocalizations l10n) {
    if (_isCheckingInteractions) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Đang kiểm tra tương tác thuốc...',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    if (_interactionError != null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _interactionError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _refreshInteractionSummary,
              child: Text(l10n.commonRetry, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (!_interactionSummary.hasInteractions ||
        _interactionSummary.requestedDrugNames.length < 2) {
      return const SizedBox.shrink();
    }

    final severity = _severityLabel(l10n, _interactionSummary.highestSeverity);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Phát hiện ${_interactionSummary.totalInteractions} tương tác ($severity)',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: () => _showInteractionDetailsSheet(l10n),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                'Chi tiết >',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInteractionDetailsSheet(AppLocalizations l10n) {
    final result = _interactionSummary.result;
    final items = result?.interactions ?? const [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Chi tiết Tương tác thuốc',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _interactionPairLabel(item),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.warning.isNotEmpty
                                ? item.warning
                                : _severityLabel(l10n, item.severity),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = _visibleDrugs;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanReviewTitle)),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: StepWizardProgress(currentStep: 1),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceHigh),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.result.guidance ?? l10n.scanReviewDefaultGuidance,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatusChip(
                      label: l10n.scanReviewDrugCount(_drugs.length),
                      color: AppColors.primary,
                    ),
                    if ((widget.result.guidance ?? '').isNotEmpty)
                      _StatusChip(
                        label: 'Gợi ý: ${widget.result.guidance}',
                        color: AppColors.info,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.scanReviewSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
                _buildInteractionPanel(l10n),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      l10n.scanReviewEmptyFilter,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: visible.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final drug = visible[index];
                      final isConfirmed = drug.mappingStatus == 'confirmed' || drug.matchScore >= 0.75;
                      final hasDbSuggestion =
                          drug.mappedDrugName != null &&
                          drug.mappedDrugName!.isNotEmpty &&
                          drug.mappedDrugName!.toLowerCase().trim() !=
                              drug.name.toLowerCase().trim();
                      final severity = _severityForDrug(drug);
                      final hasInteractionRisk = severity != null;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: hasInteractionRisk
                              ? AppColors.error.withValues(alpha: 0.06)
                              : (isConfirmed
                                  ? AppColors.surface
                                  : AppColors.warning.withValues(alpha: 0.04)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: hasInteractionRisk
                                ? AppColors.error.withValues(alpha: 0.55)
                                : (isConfirmed
                                    ? AppColors.border
                                    : AppColors.warning.withValues(alpha: 0.4)),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _StatusChip(
                                  label: isConfirmed ? '✅ Đã xác thực DB' : '⚠️ Cần kiểm tra lại',
                                  color: isConfirmed ? AppColors.success : AppColors.warning,
                                ),
                                const Spacer(),
                                if (hasInteractionRisk)
                                  _StatusChip(
                                    label: 'Tương tác (${_severityLabel(l10n, severity)})',
                                    color: AppColors.error,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              drug.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (drug.dosage != null && drug.dosage!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Hàm lượng: ${drug.dosage}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  ),
                                  if (drug.frequency > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceSoft,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Lịch: ${drug.frequency} lần/ngày',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (hasDbSuggestion) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.verified_outlined,
                                    size: 14,
                                    color: AppColors.success,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Chuẩn DB: ${drug.mappedDrugName!}',
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (drug.ocrText.isNotEmpty &&
                                drug.ocrText.toLowerCase().trim() !=
                                    drug.name.toLowerCase().trim()) ...[
                              const SizedBox(height: 4),
                              Text(
                                l10n.scanReviewOcrRaw(drug.ocrText),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () => _editDrug(drug),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: Text(l10n.scanReviewEdit),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => _removeDrug(drug),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                  ),
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  label: Text(l10n.scanReviewRemove),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addDrugManually,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(l10n.scanReviewAddDrug),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/create/scan'),
                        icon: const Icon(
                          Icons.document_scanner_outlined,
                          size: 18,
                        ),
                        label: Text(l10n.scanReviewRescan),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: (_drugs.isEmpty || _isCheckingInteractions)
                      ? null
                      : _continue,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l10n.scanReviewContinue(_drugs.length)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
