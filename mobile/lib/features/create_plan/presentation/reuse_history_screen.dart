import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/session/current_user_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/data/plan_cache.dart';
import '../data/plan_repository.dart';
import '../domain/plan.dart';

/// Screen: Dùng lại từ kế hoạch cũ đã hoàn thành hoặc đã kết thúc.
class ReuseHistoryScreen extends ConsumerWidget {
  const ReuseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansFuture = ref.watch(_archivedPlansProvider.future);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dùng lại kế hoạch cũ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/create'),
        ),
      ),
      body: FutureBuilder<List<Plan>>(
        future: plansFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              onRetry: () => ref.invalidate(_archivedPlansProvider),
            );
          }

          final plans = snapshot.data ?? const <Plan>[];
          if (plans.isEmpty) {
            return _EmptyState(onScanNow: () => context.go('/create'));
          }

          final df = DateFormat('dd/MM/yyyy');
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_archivedPlansProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: plans.length,
              separatorBuilder: (_, i) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final plan = plans[index];
                return _ReuseCard(
                  drugCount: plan.drugs.length,
                  scannedAt: _planDateRange(plan, df),
                  qualityState: plan.hasEnded ? 'DONE' : 'ACTIVE',
                  canReuse: plan.drugs.isNotEmpty,
                  title: plan.drugName,
                  subtitle: plan.scheduleSummary,
                  onTap: () => context.go(
                    '/create/edit',
                    extra: plan.drugs
                        .map(
                          (drug) => PlanDrugItem(
                            name: drug.drugName,
                            dosage: drug.dosage ?? '',
                            totalDays: plan.totalDays ?? 7,
                            notes: drug.notes ?? '',
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  static String _planDateRange(Plan plan, DateFormat df) {
    final start = plan.parsedStartDate;
    final end = plan.parsedEndDate;
    if (start == null && end == null) return 'Không rõ thời gian';
    if (start != null && end != null) {
      return '${df.format(start)} - ${df.format(end)}';
    }
    return df.format((start ?? end)!.toLocal());
  }
}

final _archivedPlansProvider = FutureProvider<List<Plan>>((ref) async {
  final userStore = ref.read(currentUserStoreProvider);
  final userId = await userStore.getCurrentUserId();

  try {
    final repo = ref.read(planRepositoryProvider);
    final plans = await repo.getPlans(activeOnly: false);
    if (userId != null && userId.isNotEmpty) {
      await ref
          .read(planCacheProvider)
          .save(userId: userId, activeOnly: false, plans: plans);
    }
    final archived = plans.where((plan) => plan.hasEnded).toList()
      ..sort((a, b) {
        final aDate =
            a.parsedEndDate ??
            a.parsedStartDate ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.parsedEndDate ??
            b.parsedStartDate ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    return archived;
  } catch (_) {
    if (userId == null || userId.isEmpty) {
      rethrow;
    }
    final cached = await ref
        .read(planCacheProvider)
        .load(userId: userId, activeOnly: false);
    final archived = cached.where((plan) => plan.hasEnded).toList()
      ..sort((a, b) {
        final aDate =
            a.parsedEndDate ??
            a.parsedStartDate ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.parsedEndDate ??
            b.parsedStartDate ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    if (archived.isNotEmpty) {
      return archived;
    }
    rethrow;
  }
});

// ---------------------------------------------------------------------------
// Reuse card — 1 lần quét trong danh sách
// ---------------------------------------------------------------------------

class _ReuseCard extends StatelessWidget {
  const _ReuseCard({
    required this.title,
    required this.subtitle,
    required this.drugCount,
    required this.scannedAt,
    required this.qualityState,
    required this.canReuse,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int drugCount;
  final String scannedAt;
  final String qualityState;
  final bool canReuse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (qLabel, qColor) = _qualityInfo(qualityState);
    final accent = canReuse ? AppColors.success : AppColors.textMuted;

    return InkWell(
      onTap: canReuse ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: canReuse
                ? AppColors.success.withValues(alpha: 0.35)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history_rounded, color: accent, size: 22),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: canReuse
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$drugCount thuốc · $subtitle',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    scannedAt,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Quality badge + action hint
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: qColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    qLabel,
                    style: TextStyle(
                      color: qColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Icon(
                  canReuse ? Icons.chevron_right : Icons.block_outlined,
                  color: canReuse ? AppColors.textMuted : AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static (String, Color) _qualityInfo(String state) {
    switch (state) {
      case 'DONE':
        return ('Kế hoạch cũ', AppColors.success);
      case 'ACTIVE':
        return ('Đang chạy', AppColors.warning);
      default:
        return ('Kế hoạch', AppColors.textMuted);
    }
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScanNow});

  final VoidCallback onScanNow;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.history_outlined,
                    size: 56,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Chưa có kế hoạch cũ nào',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sau khi một kế hoạch kết thúc, bạn có thể dùng lại danh sách thuốc ở đây.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: onScanNow,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Tạo kế hoạch mới'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_outlined,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Không tải được kế hoạch cũ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kiểm tra kết nối và thử lại.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
