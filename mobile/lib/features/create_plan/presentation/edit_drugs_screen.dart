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
import 'widgets/drug_entry_sheet.dart';

/// Screen: Nhập tay hoặc chỉnh sửa nâng cao danh sách thuốc → lập lịch.
/// Vai trò còn lại: nhập tay từ đầu (từ /create/edit không có initial drugs)
/// hoặc chỉnh sửa nâng cao trước khi lập lịch.
class EditDrugsScreen extends ConsumerStatefulWidget {
  /// Pre-filled drugs từ OCR hoặc trống cho nhập tay.
  final List<PlanDrugItem> initialDrugs;
  final Plan? existingPlan;

  const EditDrugsScreen({
    super.key,
    this.initialDrugs = const [],
    this.existingPlan,
  });

  @override
  ConsumerState<EditDrugsScreen> createState() => _EditDrugsScreenState();
}

class _EditDrugsScreenState extends ConsumerState<EditDrugsScreen> {
  late List<PlanDrugItem> _drugs;
  PlanInteractionSummary _interactionSummary = PlanInteractionSummary.empty();
  bool _isCheckingInteractions = false;
  String? _interactionError;
  int _interactionRequestId = 0;

  @override
  void initState() {
    super.initState();
    _drugs = List.from(widget.initialDrugs);
    _refreshInteractionSummary();
  }

  // -------------------------------------------------------------------------
  // Add drug — with DB search suggestion
  // -------------------------------------------------------------------------

  Future<void> _addDrug() async {
    final result = await showModalBottomSheet<PlanDrugItem?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DrugEntrySheet(ref: ref),
    );
    if (result != null) {
      setState(() => _drugs.add(result));
      _refreshInteractionSummary();
    }
  }

  // -------------------------------------------------------------------------
  // Edit drug — with DB search suggestion
  // -------------------------------------------------------------------------

  Future<void> _editDrug(int index) async {
    final current = _drugs[index];
    final result = await showModalBottomSheet<PlanDrugItem?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DrugEntrySheet(ref: ref, initial: current),
    );
    if (result != null) {
      setState(() => _drugs[index] = result);
      _refreshInteractionSummary();
    }
  }

  void _removeDrug(int index) {
    setState(() => _drugs.removeAt(index));
    _refreshInteractionSummary();
  }

  Future<void> _refreshInteractionSummary() async {
    final requestId = ++_interactionRequestId;
    setState(() {
      _isCheckingInteractions = true;
      _interactionError = null;
    });

    try {
      final checker = ref.read(planInteractionCheckerProvider);
      final summary = await checker.checkPlanDrugs(_drugs);
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

  String? _severityForDrug(PlanDrugItem drug) {
    return _interactionSummary.severityForDrugName(drug.name);
  }

  Future<void> _continueToSchedule() async {
    if (_interactionSummary.hasInteractions) {
      final proceed = await _showInteractionConfirmDialog();
      if (!proceed) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    context.go(
      '/create/schedule',
      extra: PlanEditFlowArgs(
        drugs: _drugs,
        existingPlan: widget.existingPlan,
        source: widget.existingPlan == null ? 'manual' : 'plan_edit',
      ),
    );
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

  Widget _buildContinueFooter(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceHigh),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_drugs.isEmpty || _isCheckingInteractions)
              ? null
              : _continueToSchedule,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(l10n.editDrugsContinue(_drugs.length)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editDrugsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (widget.existingPlan != null) {
              context.go('/plans/${widget.existingPlan!.id}');
            } else {
              context.go('/create');
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDrug,
        backgroundColor: AppColors.primary,
        tooltip: l10n.editDrugsAddTooltip,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _buildContinueFooter(l10n),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: StepWizardProgress(currentStep: 2),
          ),
          _buildInteractionPanel(l10n),
          // Drug list
          Expanded(
            child: _drugs.isEmpty
                ? _buildEmpty(l10n)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _drugs.length,
                    itemBuilder: (ctx, i) => _buildDrugCard(i),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_outlined, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            l10n.editDrugsEmptyTitle,
            style: TextStyle(color: AppColors.textMuted, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.editDrugsEmptyHint,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _addDrug,
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.editDrugsEmptyAddFirst),
          ),
        ],
      ),
    );
  }

  Widget _buildDrugCard(int index) {
    final drug = _drugs[index];
    final severity = _severityForDrug(drug);
    final hasInteractionRisk = severity != null;
    final l10n = AppLocalizations.of(context);

    return Card(
      color: hasInteractionRisk
          ? AppColors.error.withValues(alpha: 0.06)
          : AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasInteractionRisk
              ? AppColors.error.withValues(alpha: 0.55)
              : AppColors.border,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: Icon(Icons.medication, color: AppColors.primary, size: 20),
        ),
        title: Text(
          drug.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasInteractionRisk)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'Có tương tác (${_severityLabel(l10n, severity)})',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (drug.dosage.isNotEmpty)
              Text(
                drug.dosage,
                style: const TextStyle(color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _editDrug(index),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: AppColors.error,
              ),
              onPressed: () => _removeDrug(index),
            ),
          ],
        ),
      ),
    );
  }
}
