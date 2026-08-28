import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/session/current_user_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../create_plan/data/plan_repository.dart';
import '../../create_plan/domain/plan.dart';
import '../../home/data/plan_cache.dart';
import '../../home/data/plan_notifier.dart';
import '../../home/data/today_schedule_notifier.dart';

class PlanDetailScreen extends ConsumerStatefulWidget {
  const PlanDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen> {
  bool _isLoading = true;
  String? _error;
  Plan? _plan;
  late DateTime _startDate;
  int _totalDays = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = ref.read(planRepositoryProvider);
      final plan = await repo.getPlanById(widget.planId);
      final userStore = ref.read(currentUserStoreProvider);
      final userId = await userStore.getCurrentUserId();
      if (userId != null && userId.isNotEmpty) {
        final cache = ref.read(planCacheProvider);
        final cachedAll = await cache.load(userId: userId, activeOnly: false);
        final mergedById = <String, Plan>{
          for (final item in cachedAll) item.id: item,
        };
        mergedById[plan.id] = plan;
        final merged = mergedById.values.toList();
        await cache.save(userId: userId, activeOnly: false, plans: merged);
      }
      _applyPlan(plan);
      setState(() {
        _plan = plan;
        _isLoading = false;
      });
    } catch (e) {
      final userStore = ref.read(currentUserStoreProvider);
      final userId = await userStore.getCurrentUserId();
      if (userId != null && userId.isNotEmpty) {
        final cache = ref.read(planCacheProvider);
        final cached = await cache.load(userId: userId, activeOnly: false);
        final matched = cached.where((item) => item.id == widget.planId);
        if (matched.isNotEmpty) {
          final offlinePlan = matched.first;
          _applyPlan(offlinePlan);
          setState(() {
            _plan = offlinePlan;
            _error = 'Đang hiển thị dữ liệu offline cho kế hoạch này.';
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openDrugEditor() {
    final current = _plan;
    if (current == null) return;

    context.go('/create/edit', extra: PlanEditFlowArgs.fromPlan(current));
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/plans');
  }

  void _applyPlan(Plan plan) {
    _totalDays = plan.totalDays ?? 7;
    _startDate = DateTime.tryParse(plan.startDate) ?? DateTime.now();
  }

  Future<void> _deactivate() async {
    final current = _plan;
    if (current == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kết thúc kế hoạch?'),
        content: const Text(
          'Kế hoạch sẽ được ngừng kích hoạt và không nhắc nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kết thúc'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = ref.read(planRepositoryProvider);
      await repo.deletePlan(current.id);
      ref.invalidate(planNotifierProvider);
      ref.invalidate(todayScheduleNotifierProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã kết thúc kế hoạch')));
      context.go('/plans');
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _reactivate() async {
    final current = _plan;
    if (current == null) return;
    try {
      final repo = ref.read(planRepositoryProvider);
      final updated = await repo.setPlanActive(current.id, true);
      ref.invalidate(planNotifierProvider);
      ref.invalidate(todayScheduleNotifierProvider);
      setState(() => _plan = updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã kích hoạt lại kế hoạch')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_plan == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chi tiết kế hoạch'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
        ),
        body: Center(child: Text(_error ?? 'Không tải được kế hoạch')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết kế hoạch'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
        actions: [
          IconButton(
            onPressed: _openDrugEditor,
            icon: const Icon(Icons.edit_note_rounded),
            tooltip: 'Sửa thuốc và lịch',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _plan!.drugName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'Từ ${DateFormat('dd/MM/yyyy').format(_startDate)} • $_totalDays ngày',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(
                      'Thuốc ${_plan!.drugs.length}',
                      AppColors.primaryDark,
                    ),
                    _pill('Giờ ${_plan!.slots.length}', AppColors.info),
                    _pill(
                      _plan!.isActive ? 'Đang chạy' : 'Đã kết thúc',
                      _plan!.isActive ? AppColors.success : AppColors.textMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('THUỐC TRONG KẾ HOẠCH'),
          const SizedBox(height: 8),
          ..._plan!.drugs.map(
            (drug) => _sectionCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.medication_outlined,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          drug.drugName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (drug.dosage != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            drug.dosage!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          _sectionLabel('LỊCH UỐNG'),
          const SizedBox(height: 8),
          ..._plan!.slots.map(
            (slot) => _sectionCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 18,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        slot.time,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...slot.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${item.drugName}: ${item.pills} viên',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if ((_plan!.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            _sectionLabel('GHI CHÚ'),
            const SizedBox(height: 8),
            _sectionCard(child: Text(_plan!.notes!)),
          ],
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ElevatedButton.icon(
            onPressed: _openDrugEditor,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Chỉnh sửa thuốc và lịch'),
          ),
          const SizedBox(height: 8),
          if (_plan!.isActive)
            OutlinedButton.icon(
              onPressed: _deactivate,
              icon: const Icon(
                Icons.pause_circle_outline,
                color: AppColors.error,
              ),
              label: const Text(
                'Kết thúc kế hoạch',
                style: TextStyle(color: AppColors.error),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _reactivate,
              icon: const Icon(
                Icons.play_circle_outline,
                color: AppColors.success,
              ),
              label: const Text(
                'Kích hoạt lại',
                style: TextStyle(color: AppColors.success),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.success),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child, EdgeInsetsGeometry? margin}) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: child,
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    ),
  );
}
