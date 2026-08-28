import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../data/drug_interaction_repository.dart';

class ActiveIngredientInteractionsScreen extends ConsumerStatefulWidget {
  const ActiveIngredientInteractionsScreen({
    super.key,
    required this.ingredientName,
  });

  final String ingredientName;

  @override
  ConsumerState<ActiveIngredientInteractionsScreen> createState() =>
      _ActiveIngredientInteractionsScreenState();
}

class _ActiveIngredientInteractionsScreenState
    extends ConsumerState<ActiveIngredientInteractionsScreen> {
  InteractionCheckResult? _result;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(drugInteractionRepositoryProvider)
          .getByActiveIngredient(widget.ingredientName);
      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = toFriendlyNetworkMessage(
          e,
          genericMessage:
              'Không thể tải hồ sơ tương tác của hoạt chất này. Vui lòng thử lại.',
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ hoạt chất')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.science_outlined,
                      color: AppColors.primaryDark,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.ingredientName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Hiển thị toàn bộ tương tác đã được lưu cục bộ cho hoạt chất này.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _DetailMessageCard(
                icon: Icons.error_outline,
                color: AppColors.error,
                message: _error!,
              )
            else if (_result == null)
              const _DetailMessageCard(
                icon: Icons.info_outline,
                color: AppColors.textSecondary,
                message: 'Chưa có dữ liệu để hiển thị.',
              )
            else ...[
              _ResultSummaryCard(result: _result!),
              const SizedBox(height: 12),
              if (!_result!.hasInteractions)
                _DetailMessageCard(
                  icon: Icons.verified_user_outlined,
                  color: AppColors.success,
                  message:
                      _result!.message ??
                      'Chưa ghi nhận tương tác trong dữ liệu hiện tại.',
                )
              else
                for (final group
                    in _result!.groups.isNotEmpty
                        ? _result!.groups
                        : [
                            InteractionGroup(
                              severity: _result!.highestSeverity,
                              severityOriginal:
                                  _result!.interactions.first.severityOriginal,
                              count: _result!.interactions.length,
                              interactions: _result!.interactions,
                            ),
                          ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InteractionGroupCard(group: group),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultSummaryCard extends StatelessWidget {
  const _ResultSummaryCard({required this.result});

  final InteractionCheckResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SeverityBadge(
            label: _severityLabel(result.highestSeverity),
            severity: result.highestSeverity,
          ),
          _InfoChip(label: 'Tổng: ${result.totalInteractions}'),
          if (result.message?.trim().isNotEmpty == true)
            _InfoChip(label: result.message!.trim()),
        ],
      ),
    );
  }
}

class _InteractionGroupCard extends StatelessWidget {
  const _InteractionGroupCard({required this.group});

  final InteractionGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SeverityBadge(
                label: _severityLabel(group.severity),
                severity: group.severity,
              ),
              const SizedBox(width: 8),
              Text(
                '${group.count} tương tác',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in group.interactions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InteractionItemCard(item: item),
            ),
        ],
      ),
    );
  }
}

class _InteractionItemCard extends StatelessWidget {
  const _InteractionItemCard({required this.item});

  final InteractionItem item;

  @override
  Widget build(BuildContext context) {
    final pairText = item.ingredientB.trim().isEmpty
        ? item.ingredientA
        : '${item.ingredientA} + ${item.ingredientB}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
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
                label: _severityLabel(item.severity),
                severity: item.severity,
              ),
            ],
          ),
          if (item.warning.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.warning,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailMessageCard extends StatelessWidget {
  const _DetailMessageCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
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
        color: palette.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.$2,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

(Color, Color) _severityPalette(String severity) {
  switch (severity) {
    case 'contraindicated':
      return (AppColors.severityCriticalBg, AppColors.severityCriticalFg);
    case 'major':
      return (AppColors.severityHighBg, AppColors.severityHighFg);
    case 'moderate':
      return (AppColors.severityModerateBg, AppColors.severityModerateFg);
    case 'minor':
      return (AppColors.severityLowBg, AppColors.severityLowFg);
    case 'caution':
      return (AppColors.severityInfoBg, AppColors.severityInfoFg);
    default:
      return (AppColors.surfaceSoft, AppColors.textSecondary);
  }
}

String _severityLabel(String severity) {
  switch (severity) {
    case 'contraindicated':
      return 'Chống chỉ định';
    case 'major':
      return 'Nghiêm trọng';
    case 'moderate':
      return 'Trung bình';
    case 'minor':
      return 'Nhẹ';
    case 'caution':
      return 'Thận trọng';
    default:
      return 'Chưa xác định';
  }
}
