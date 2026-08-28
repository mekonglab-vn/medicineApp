import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/session/current_user_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../create_plan/data/plan_repository.dart';
import '../../create_plan/domain/plan.dart';
import '../../home/data/plan_cache.dart';

class PlanListScreen extends ConsumerStatefulWidget {
  const PlanListScreen({super.key});

  @override
  ConsumerState<PlanListScreen> createState() => _PlanListScreenState();
}

class _PlanListScreenState extends ConsumerState<PlanListScreen> {
  bool _isLoading = true;
  String? _error;
  List<Plan> _plans = const [];
  bool _isOfflineData = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isOfflineData = false;
    });
    try {
      final repo = ref.read(planRepositoryProvider);
      final plans = await repo.getPlans(activeOnly: false);
      final userStore = ref.read(currentUserStoreProvider);
      final userId = await userStore.getCurrentUserId();
      if (userId != null && userId.isNotEmpty) {
        final cache = ref.read(planCacheProvider);
        await cache.save(userId: userId, activeOnly: false, plans: plans);
      }
      setState(() {
        _plans = plans;
        _isOfflineData = false;
        _isLoading = false;
      });
    } catch (e) {
      final userStore = ref.read(currentUserStoreProvider);
      final userId = await userStore.getCurrentUserId();
      if (userId != null && userId.isNotEmpty) {
        final cache = ref.read(planCacheProvider);
        final cached = await cache.load(userId: userId, activeOnly: false);
        if (cached.isNotEmpty) {
          setState(() {
            _plans = cached;
            _isOfflineData = true;
            _error = toFriendlyNetworkMessage(
              e,
              genericMessage:
                  'Không tải được dữ liệu mới, đang dùng dữ liệu offline.',
            );
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _error = toFriendlyNetworkMessage(
          e,
          genericMessage:
              'Không tải được danh sách kế hoạch. Vui lòng thử lại.',
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePlans = _plans.where((plan) => plan.isCurrentPlan).toList();
    final activeSlots = activePlans.fold<int>(
      0,
      (sum, plan) => sum + plan.slots.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kế hoạch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => context.push('/create'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(
                children: [
                  SizedBox(
                    height: 500,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : _error != null && _plans.isEmpty
            ? ListView(
                children: [
                  SizedBox(
                    height: 500,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.error,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(_error!, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_isOfflineData)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            color: AppColors.warning,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Bạn đang xem dữ liệu offline đã lưu trên thiết bị.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  _SummaryHeader(
                    activeCount: activePlans.length,
                    totalCount: activePlans.length,
                    totalSlots: activeSlots,
                  ),
                  const SizedBox(height: 20),
                  _SectionTitle(
                    title: 'Đang kích hoạt',
                    subtitle: activePlans.isEmpty
                        ? 'Chưa có kế hoạch nào đang chạy'
                        : '${activePlans.length} kế hoạch đang nhắc thuốc',
                  ),
                  const SizedBox(height: 10),
                  if (activePlans.isEmpty)
                    _EmptyPlanCard(
                      message:
                          'Bạn chưa có kế hoạch đang kích hoạt. Quét đơn mới hoặc tạo thủ công.',
                    )
                  else
                    ...activePlans.map((plan) => _PlanTile(plan: plan)),
                  const SizedBox(height: 16),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('Tạo kế hoạch'),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.activeCount,
    required this.totalCount,
    required this.totalSlots,
  });

  final int activeCount;
  final int totalCount;
  final int totalSlots;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(label: 'Đang chạy', value: '$activeCount'),
          ),
          Expanded(
            child: _SummaryMetric(label: 'Tổng', value: '$totalCount'),
          ),
          Expanded(
            child: _SummaryMetric(label: 'Khung giờ', value: '$totalSlots'),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

class _EmptyPlanCard extends StatelessWidget {
  const _EmptyPlanCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

class _PlanTile extends ConsumerWidget {
  const _PlanTile({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = plan.isCurrentPlan
        ? AppColors.success
        : AppColors.textMuted;
    final statusLabel = plan.isCurrentPlan ? 'Đang chạy' : 'Đã kết thúc';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: ListTile(
        onTap: () => context.go('/plans/${plan.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: const Icon(
            Icons.medication_outlined,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          plan.drugName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${plan.drugs.length} thuốc · ${plan.slots.length} khung giờ',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              statusLabel,
              style: TextStyle(color: statusColor, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 120,
              child: Text(
                plan.hasVariableDoseSchedule
                    ? 'Số viên theo từng giờ'
                    : plan.scheduleSummary,
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
