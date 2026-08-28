import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:medicine_app/l10n/app_localizations.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/data/profile_notifier.dart';
import '../data/plan_notifier.dart';
import '../data/today_schedule_notifier.dart';
import '../domain/today_schedule.dart';
import 'widgets/dose_timeline_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(planNotifierProvider);
    final todayAsync = ref.watch(todayScheduleNotifierProvider);

    ref.listen<AsyncValue<TodaySchedule>>(todayScheduleNotifierProvider, (
      previous,
      next,
    ) async {
      if (next.hasValue) {
        final synced = await ref
            .read(todayScheduleNotifierProvider.notifier)
            .flushOfflineQueue();
        if (synced > 0 && context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.homeSyncSuccess(synced)),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    });

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: toFriendlyNetworkMessage(
            e,
            genericMessage: 'Không tải được dữ liệu hôm nay. Vui lòng thử lại.',
          ),
          onRetry: () => ref.read(planNotifierProvider.notifier).refresh(),
        ),
        data: (state) {
          final stateError = state.error == null
              ? null
              : Exception(state.error);

          if (!state.hasPlans && state.error != null) {
            return _ErrorView(
              message: toFriendlyNetworkMessage(
                stateError!,
                genericMessage:
                    'Không tải được dữ liệu hôm nay. Vui lòng thử lại.',
              ),
              onRetry: () => ref.read(planNotifierProvider.notifier).refresh(),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(planNotifierProvider.notifier).refresh();
              await ref.read(todayScheduleNotifierProvider.notifier).refresh();
            },
            child: state.hasPlans
                ? _DashboardView(todayAsync: todayAsync)
                : _OnboardingView(isOfflineCache: state.isFromCache),
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.cloud_off_rounded, size: 54, color: AppColors.textMuted),
        const SizedBox(height: 18),
        Text(
          'Không tải được dữ liệu hôm nay',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: Text(AppLocalizations.of(context).commonRetry),
        ),
      ],
    );
  }
}
class _OnboardingView extends StatelessWidget {
  const _OnboardingView({this.isOfflineCache = false});

  final bool isOfflineCache;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        if (isOfflineCache)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_off_outlined, color: AppColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đang dùng dữ liệu offline. Kéo xuống để thử đồng bộ lại.',
                  ),
                ),
              ],
            ),
          ),
        const _DateHeader(),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.surfaceSoft, AppColors.background],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.medication_liquid_rounded,
                  color: AppColors.primaryDark,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.homeOnboardingTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.homeOnboardingSubtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => context.push('/create/scan'),
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(l10n.homeActionScan),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/create/edit'),
                      icon: const Icon(Icons.edit_note),
                      label: Text(l10n.homeActionManual),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/create/reuse'),
                      icon: const Icon(Icons.history_outlined),
                      label: Text(l10n.homeActionHistory),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _LookupPrimaryCard(onTap: () => context.push('/lookup')),
        const SizedBox(height: 14),
        const _SectionLabel(title: 'Quản lý lịch uống'),
        const SizedBox(height: 10),
        _QuickActionGrid(
          actions: [
            _QuickActionItem(
              title: l10n.homeActionPlans,
              subtitle: l10n.homeActionPlansSubtitle,
              icon: Icons.calendar_month_rounded,
              onTap: () => context.go('/plans'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DashboardView extends ConsumerWidget {
  const _DashboardView({required this.todayAsync});

  final AsyncValue<TodaySchedule> todayAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canMark = !todayAsync.isLoading;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 100),
      children: [
        const _ProfileHeaderSelector(),
        const _DateHeader(),
        const SizedBox(height: AppSpacing.md),
        todayAsync.when(
          loading: () => const _TodayLoadingCard(),
          error: (e, _) => _TodayErrorCard(
            message: toFriendlyNetworkMessage(
              e,
              genericMessage:
                  'Không tải được lịch uống thuốc hôm nay. Vui lòng thử lại.',
            ),
            onRetry: () =>
                ref.read(todayScheduleNotifierProvider.notifier).refresh(),
          ),
          data: (today) {
            final now = DateTime.now();
            final sortedDoses = List<TodayDose>.from(today.doses)
              ..sort((a, b) => a.comparePriority(b, now));
            final featuredDose = sortedDoses.isNotEmpty
                ? sortedDoses.first
                : null;

            // Sort all doses by scheduled time for timeline view
            final timelineDoses = List<TodayDose>.from(today.doses)
              ..sort((a, b) {
                final aTime = a.scheduledLocalDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
                final bTime = b.scheduledLocalDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
                return aTime.compareTo(bTime);
              });

            Future<void> onMarkDose(TodayDose dose, String status) async {
              final result = await ref
                  .read(todayScheduleNotifierProvider.notifier)
                  .markDose(dose: dose, status: status);
              if (!context.mounted) return;
              final l10n = AppLocalizations.of(context);

              if (result == MarkDoseResult.failed) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lỗi lưu liều uống. Vui lòng thử lại.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              final successLabel = status == 'taken'
                  ? l10n.homeDoseTakenStatus(dose.primaryTitle)
                  : l10n.homeDoseSkippedStatus(dose.primaryTitle);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result == MarkDoseResult.synced
                        ? successLabel
                        : l10n.homeDoseOfflineStatus,
                  ),
                  backgroundColor: result == MarkDoseResult.synced
                      ? AppColors.success
                      : AppColors.warning,
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (today.doses.isEmpty || featuredDose == null)
                  _TodayEmptyCard(
                    onScan: () => context.push('/create/scan'),
                    onCreatePlan: () => context.push('/create/edit'),
                    onViewPlans: () => context.go('/plans'),
                  )
                else ...[
                  _TodayProgressCard(doses: today.doses),
                  const SizedBox(height: AppSpacing.md),
                  _TodayMainDoseCard(
                    dose: featuredDose,
                    canMark: canMark,
                    onTap: () => context.go('/plans/${featuredDose.planId}'),
                    onTaken: () => onMarkDose(featuredDose, 'taken'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text(
                    'Lịch uống trong ngày',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...timelineDoses.map((dose) => DoseTimelineCard(
                        dose: dose,
                        canMark: canMark,
                        onTap: () => context.go('/plans/${dose.planId}'),
                        onTaken: () => onMarkDose(dose, 'taken'),
                        onSkipped: () => onMarkDose(dose, 'skipped'),
                      )),
                ],
                const SizedBox(height: AppSpacing.lg),
                _QuickActionStrip(
                  onScan: () => context.push('/create/scan'),
                  onManual: () => context.push('/create/edit'),
                  onLookup: () => context.push('/lookup'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _formatHomeDate(DateTime date) {
  return DateFormat('d MMMM, yyyy', 'vi_VN').format(date);
}

bool _isCompactHomeCard(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 390;
}

String _formatCountdownText(DateTime scheduled, DateTime now) {
  final diff = scheduled.difference(now);
  if (diff.inMinutes > 0) {
    if (diff.inHours > 0) {
      return 'Còn ${diff.inHours} giờ ${diff.inMinutes.remainder(60)} phút';
    }
    return 'Còn ${diff.inMinutes} phút';
  }
  final overdue = diff.abs();
  if (overdue.inHours > 0) {
    return 'Trễ ${overdue.inHours} giờ ${overdue.inMinutes.remainder(60)} phút';
  }
  return 'Trễ ${overdue.inMinutes} phút';
}

String _doseSummaryText(TodayDose dose) {
  final medications = dose.medications
      .where((item) => item.drugName.trim().isNotEmpty)
      .toList();

  if (medications.isNotEmpty) {
    if (medications.length == 1) {
      final item = medications.first;
      return '${item.drugName}: ${item.pills} viên';
    }

    final preview = medications
        .take(2)
        .map((item) => item.drugName.trim())
        .join(', ');
    final extra = medications.length - 2;
    final totalPills = medications.fold<int>(
      0,
      (sum, item) => sum + item.pills,
    );
    return extra > 0
        ? '$preview và $extra thuốc khác • $totalPills viên'
        : '$preview • $totalPills viên';
  }

  final dosage = dose.dosage?.trim();
  if (dosage != null && dosage.isNotEmpty) {
    return dosage;
  }

  return '${dose.pillsPerDose ?? 1} viên/liều';
}

String _doseSessionLabel(TodayDose dose) {
  final scheduled = dose.scheduledLocalDateTime;
  if (scheduled == null) return 'Liều';

  final hour = scheduled.hour;
  if (hour >= 5 && hour < 11) return 'Buổi sáng';
  if (hour >= 11 && hour < 14) return 'Buổi trưa';
  if (hour >= 14 && hour < 18) return 'Buổi chiều';
  return 'Buổi tối';
}

class _DateHeader extends StatelessWidget {
  const _DateHeader();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel = _formatHomeDate(now);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).homeTitleToday,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                dateLabel,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 6),
              Text(AppLocalizations.of(context).homeTodayDrugs),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayProgressCard extends StatelessWidget {
  const _TodayProgressCard({required this.doses});

  final List<TodayDose> doses;

  @override
  Widget build(BuildContext context) {
    final taken = doses.where((d) => d.status == 'taken').length;
    final total = doses.length;
    final pct = total == 0 ? 0.0 : (taken / total);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.task_alt_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Tiến trình hôm nay',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              Text(
                '$taken / $total liều',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayMainDoseCard extends StatelessWidget {
  const _TodayMainDoseCard({
    required this.dose,
    required this.canMark,
    required this.onTap,
    required this.onTaken,
  });

  final TodayDose dose;
  final bool canMark;
  final VoidCallback onTap;
  final VoidCallback onTaken;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheduled = dose.scheduledLocalDateTime;
    final compact = _isCompactHomeCard(context);
    final status = dose.effectiveStatus(now);
    final isPending = status == 'pending';
    final statusMeta = switch (status) {
      'taken' => ('Đã uống', AppColors.success, Icons.check_circle_rounded),
      'skipped' => ('Bỏ qua', AppColors.warning, Icons.remove_circle_rounded),
      'missed' => ('Đã quên', AppColors.error, Icons.error_rounded),
      _ when dose.isDueNow(now) => (
        'Đến giờ uống',
        AppColors.primaryDark,
        Icons.alarm_rounded,
      ),
      _ when dose.isUpcomingSoon(now) => (
        'Sắp đến giờ',
        AppColors.info,
        Icons.notifications_active_rounded,
      ),
      _ => ('Chờ đến giờ', AppColors.primaryDark, Icons.schedule_rounded),
    };

    final actionLabel = switch (status) {
      'taken' => 'Đã uống xong',
      'skipped' => 'Đã bỏ qua',
      'missed' => 'Đã quên',
      _ when dose.isDueNow(now) => 'Đã uống',
      _ when dose.isUpcomingSoon(now) => 'Sắp đến giờ',
      _ => 'Chờ đến giờ',
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 14 : 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 78 : 88,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Text(
                    dose.time,
                    style: TextStyle(
                      fontSize: compact ? 24 : 28,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _doseSessionLabel(dose),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 12 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          statusMeta.$1,
                          style: TextStyle(
                            color: statusMeta.$2,
                            fontWeight: FontWeight.w900,
                            fontSize: compact ? 13 : 14,
                          ),
                        ),
                      ),
                      if (scheduled != null)
                        Text(
                          _formatCountdownText(scheduled, now),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dose.primaryTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _doseSummaryText(dose),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isPending && (dose.isDueNow(now) || dose.isUpcomingSoon(now)))
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: canMark ? onTaken : null,
                        icon: const Icon(Icons.check_circle_outline, size: 20),
                        label: const Text('Đã uống'),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusMeta.$2.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusMeta.$3, color: statusMeta.$2, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            actionLabel,
                            style: TextStyle(
                              color: statusMeta.$2,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionStrip extends StatelessWidget {
  const _QuickActionStrip({
    required this.onScan,
    required this.onManual,
    required this.onLookup,
  });

  final VoidCallback onScan;
  final VoidCallback onManual;
  final VoidCallback onLookup;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StripTile(
            label: 'Quét đơn',
            icon: Icons.document_scanner_outlined,
            onTap: onScan,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StripTile(
            label: 'Nhập tay',
            icon: Icons.edit_note_rounded,
            onTap: onManual,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StripTile(
            label: 'Tra cứu',
            icon: Icons.search_rounded,
            onTap: onLookup,
          ),
        ),
      ],
    );
  }
}

class _StripTile extends StatelessWidget {
  const _StripTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primaryDark, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LookupPrimaryCard extends StatelessWidget {
  const _LookupPrimaryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.search_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.homeActionDrugLookup,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.homeActionDrugLookupSubtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 30,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.actions});

  final List<_QuickActionItem> actions;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 360 ? 1 : 2;
    final childAspectRatio = crossAxisCount == 1 ? 2.55 : 1.05;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = actions[index];
        return InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: AppColors.primaryDark),
                ),
                const Spacer(),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuickActionItem {
  _QuickActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _TodayLoadingCard extends StatelessWidget {
  const _TodayLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(AppLocalizations.of(context).homeLoadingToday)),
        ],
      ),
    );
  }
}

class _TodayErrorCard extends StatelessWidget {
  const _TodayErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            AppLocalizations.of(context).homeErrorLoadSchedule,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context).commonRetry),
          ),
        ],
      ),
    );
  }
}

class _TodayEmptyCard extends StatelessWidget {
  const _TodayEmptyCard({
    required this.onScan,
    required this.onCreatePlan,
    required this.onViewPlans,
  });

  final VoidCallback onScan;
  final VoidCallback onCreatePlan;
  final VoidCallback onViewPlans;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.event_available_rounded,
            color: AppColors.primaryDark,
            size: 36,
          ),
          const SizedBox(height: 10),
          const Text(
            'Hôm nay không có liều uống nào.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Bạn có thể quét đơn mới, nhập tay kế hoạch hoặc mở danh sách kế hoạch đang chạy.',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Quét đơn'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCreatePlan,
              icon: const Icon(Icons.edit_note),
              label: const Text('Tạo kế hoạch'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onViewPlans,
              icon: const Icon(Icons.view_list_outlined),
              label: const Text('Xem kế hoạch'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderSelector extends ConsumerWidget {
  const _ProfileHeaderSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileState = ref.watch(profileNotifierProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...profileState.profiles.map((p) {
              final selected = p.id == profileState.activeProfileId;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(
                    p.relation == 'Con'
                        ? Icons.child_care_rounded
                        : (p.relation == 'Bố' || p.relation == 'Mẹ')
                            ? Icons.elderly_rounded
                            : Icons.person_rounded,
                    size: 16,
                    color: selected ? AppColors.surface : AppColors.primaryDark,
                  ),
                  label: Text(p.name),
                  selected: selected,
                  selectedColor: AppColors.primaryDark,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.surface : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  ),
                  onSelected: (_) {
                    ref
                        .read(profileNotifierProvider.notifier)
                        .selectProfile(p.id);
                  },
                ),
              );
            }),
            IconButton.outlined(
              onPressed: () => _showAddProfileDialog(context, ref),
              icon: const Icon(Icons.add, size: 16),
              tooltip: 'Thêm hồ sơ người thân',
              style: IconButton.styleFrom(
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddProfileDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    String relation = 'Bố';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm hồ sơ người thân'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên người thân (ví dụ: Bố, Mẹ, Bé Bún)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: relation,
              items: const [
                DropdownMenuItem(value: 'Bố', child: Text('Bố')),
                DropdownMenuItem(value: 'Mẹ', child: Text('Mẹ')),
                DropdownMenuItem(value: 'Con', child: Text('Con')),
                DropdownMenuItem(value: 'Khác', child: Text('Khác')),
              ],
              onChanged: (val) => relation = val ?? 'Bố',
              decoration: const InputDecoration(labelText: 'Quan hệ'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                ref
                    .read(profileNotifierProvider.notifier)
                    .addProfile(nameCtrl.text.trim(), relation);
                Navigator.pop(context);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }
}
