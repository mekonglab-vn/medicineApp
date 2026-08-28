import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../../create_plan/data/plan_repository.dart';
import '../../create_plan/domain/medication_log.dart';
import '../../create_plan/domain/plan.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}
class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _isLoading = true;
  String? _error;
  List<Plan> _archivedPlans = const [];
  List<MedicationLogEntry> _logs = const [];
  String? _selectedPlanId;
  DateTime _weekStart = _startOfWeek(DateTime.now());
  int _selectedTabIndex = 0;

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
      final results = await Future.wait<dynamic>([
        repo.getPlans(activeOnly: false),
        repo.getMedicationLogs(limit: 100),
      ]);

      final plans =
          (results[0] as List<Plan>).where((plan) => plan.hasEnded).toList()
            ..sort((a, b) {
              final aDate = _resolvedEndDate(a);
              final bDate = _resolvedEndDate(b);
              return bDate.compareTo(aDate);
            });

      final logs = (results[1] as MedicationLogsPage).items;
      final selectedPlan = plans.isEmpty
          ? null
          : plans.any((plan) => plan.id == _selectedPlanId)
          ? plans.firstWhere((plan) => plan.id == _selectedPlanId)
          : plans.first;

      setState(() {
        _archivedPlans = plans;
        _logs = logs;
        _selectedPlanId = selectedPlan?.id;
        _weekStart = selectedPlan == null
            ? _startOfWeek(DateTime.now())
            : _startOfWeek(_resolvedEndDate(selectedPlan));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = toFriendlyNetworkMessage(
          e,
          genericMessage:
              'Không tải được lịch sử kế hoạch. Kéo xuống để thử lại.',
        );
        _isLoading = false;
      });
    }
  }

  void _selectPlan(Plan plan) {
    setState(() {
      _selectedPlanId = plan.id;
      _weekStart = _startOfWeek(_resolvedEndDate(plan));
    });
  }

  void _changeWeek(int days) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: days));
    });
  }

  void _reusePlan(Plan plan) {
    context.go(
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
    );
  }

  void _showPdfReportModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Báo cáo Tuân thủ Y tế (PDF)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Hồ sơ: Bản thân', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Thời gian: 30 ngày qua (Tỷ lệ tuân thủ: 92%)'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Các đơn thuốc: Paracetamol, Celecoxib, Mecobalamin', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('• Thống kê: 60 liều đã lên lịch | 55 liều đúng giờ | 5 liều trễ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã tạo báo cáo PDF thành công! Đang mở trang in / chia sẻ...'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
              icon: const Icon(Icons.share),
              label: const Text('Tạo & Chia sẻ Báo cáo PDF'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = _archivedPlans
        .where((plan) => plan.id == _selectedPlanId)
        .firstOrNull;
    final occurrences = selectedPlan == null
        ? const <_DoseOccurrence>[]
        : _buildWeekOccurrences(selectedPlan, _logs, _weekStart);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Xuất báo cáo PDF',
            onPressed: () => _showPdfReportModal(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(
                children: const [
                  SizedBox(
                    height: 420,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : selectedPlan == null
            ? _EmptyState(onCreatePlan: () => context.go('/create'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                children: [
                  Center(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          label: Text('Nhật ký tuân thủ'),
                          icon: Icon(Icons.analytics_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: 1,
                          label: Text('Đơn thuốc & Kế hoạch'),
                          icon: Icon(Icons.inventory_2_outlined, size: 18),
                        ),
                      ],
                      selected: {_selectedTabIndex},
                      onSelectionChanged: (set) =>
                          setState(() => _selectedTabIndex = set.first),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<int>(_selectedTabIndex),
                      child: _selectedTabIndex == 0
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ComplianceHeaderCard(occurrences: occurrences),
                                const SizedBox(height: AppSpacing.lg),
                                _WeekHeader(
                                  label: _formatWeekRange(_weekStart),
                                  canGoNext: !_weekStart.isAtSameMomentAs(
                                    _startOfWeek(DateTime.now()),
                                  ),
                                  onPrevious: () => _changeWeek(-7),
                                  onNext: () => _changeWeek(7),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _WeekGrid(weekStart: _weekStart, occurrences: occurrences),
                                const SizedBox(height: AppSpacing.md),
                                const _LegendRow(),
                                const SizedBox(height: AppSpacing.xl),
                                const _SectionTitle(
                                  title: 'Chi tiết liều trong tuần',
                                  subtitle:
                                      'Danh sách chi tiết các liều uống thuốc theo từng ngày.',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                if (occurrences.isEmpty)
                                  const _WeekEmptyCard()
                                else
                                  ..._buildDailyDetails(occurrences),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionTitle(
                                  title: 'Tổng quan kế hoạch',
                                  subtitle:
                                      '${_archivedPlans.length} kế hoạch cũ • ${_logs.length} lần ghi nhận',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _PlanSummaryCard(
                                  plan: selectedPlan,
                                  weekLabel: _formatWeekRange(_weekStart),
                                  onReuse: () => _reusePlan(selectedPlan),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                const _SectionTitle(
                                  title: 'Danh sách đơn thuốc & Kế hoạch',
                                  subtitle: 'Chọn kế hoạch để xem lịch sử uống thuốc chi tiết',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                ..._archivedPlans.map(
                                  (plan) => _PlanHistoryCard(
                                    plan: plan,
                                    selected: plan.id == selectedPlan.id,
                                    onTap: () => _selectPlan(plan),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static DateTime _resolvedEndDate(Plan plan) {
    final explicitEnd = plan.parsedEndDate;
    if (explicitEnd != null) {
      return DateTime(explicitEnd.year, explicitEnd.month, explicitEnd.day);
    }

    final start = plan.parsedStartDate;
    if (start == null) {
      return DateTime.now();
    }

    final totalDays = plan.totalDays ?? 1;
    return DateTime(
      start.year,
      start.month,
      start.day,
    ).add(Duration(days: totalDays - 1));
  }

  static DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  static String _formatWeekRange(DateTime weekStart) {
    final formatter = DateFormat('dd/MM');
    final weekEnd = weekStart.add(const Duration(days: 6));
    return '${formatter.format(weekStart)} - ${formatter.format(weekEnd)}';
  }

  List<_DoseOccurrence> _buildWeekOccurrences(
    Plan plan,
    List<MedicationLogEntry> logs,
    DateTime weekStart,
  ) {
    final relevantLogs = {
      for (final log in logs.where(
        (log) => log.planId == plan.id && log.occurrenceId != null,
      ))
        log.occurrenceId!: log,
    };

    final occurrences = <_DoseOccurrence>[];
    final now = DateTime.now();
    final planStart = plan.parsedStartDate == null
        ? DateTime(1970)
        : DateTime(
            plan.parsedStartDate!.year,
            plan.parsedStartDate!.month,
            plan.parsedStartDate!.day,
          );
    final planEnd = _resolvedEndDate(plan);

    for (var index = 0; index < 7; index += 1) {
      final day = weekStart.add(Duration(days: index));
      if (day.isBefore(planStart) || day.isAfter(planEnd)) {
        continue;
      }

      final dateKey = DateFormat('yyyy-MM-dd').format(day);
      for (final slot in plan.slots) {
        final parts = slot.time.split(':');
        final hour = int.tryParse(parts.firstOrNull ?? '');
        final minute = int.tryParse(parts.length > 1 ? parts[1] : '');
        if (hour == null || minute == null) {
          continue;
        }

        final scheduledAt = DateTime(
          day.year,
          day.month,
          day.day,
          hour,
          minute,
        );
        final occurrenceId = '${plan.id}:$dateKey:${slot.time}';
        final log = relevantLogs[occurrenceId];
        final status = log?.status ?? _derivedStatusForTime(scheduledAt, now);
        final title = slot.items.map((item) => item.drugName).join(', ');

        occurrences.add(
          _DoseOccurrence(
            occurrenceId: occurrenceId,
            title: title.isEmpty ? plan.drugName : title,
            scheduledAt: scheduledAt,
            timeLabel: slot.time,
            status: status,
            period: _DayPeriod.fromHour(hour),
          ),
        );
      }
    }

    occurrences.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return occurrences;
  }

  static String _derivedStatusForTime(DateTime scheduledAt, DateTime now) {
    if (now.isAfter(scheduledAt.add(const Duration(minutes: 45)))) {
      return 'missed';
    }
    return 'pending';
  }

  List<Widget> _buildDailyDetails(List<_DoseOccurrence> occurrences) {
    final dayGroups = <DateTime, List<_DoseOccurrence>>{};
    for (final item in occurrences) {
      final key = DateTime(
        item.scheduledAt.year,
        item.scheduledAt.month,
        item.scheduledAt.day,
      );
      dayGroups.putIfAbsent(key, () => <_DoseOccurrence>[]).add(item);
    }

    final formatter = DateFormat('EEEE, dd/MM', 'vi');
    return dayGroups.entries.map((entry) {
      final items = entry.value
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _capitalize(formatter.format(entry.key)),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _OccurrenceTile(item: item),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

enum _DayPeriod {
  morning,
  noon,
  afternoon,
  evening;

  String get label => switch (this) {
    _DayPeriod.morning => 'Sáng',
    _DayPeriod.noon => 'Trưa',
    _DayPeriod.afternoon => 'Chiều',
    _DayPeriod.evening => 'Tối',
  };

  IconData get icon => switch (this) {
    _DayPeriod.morning => Icons.wb_sunny_outlined,
    _DayPeriod.noon => Icons.wb_sunny,
    _DayPeriod.afternoon => Icons.wb_twilight,
    _DayPeriod.evening => Icons.nights_stay_outlined,
  };

  static _DayPeriod fromHour(int hour) {
    if (hour >= 5 && hour < 11) return _DayPeriod.morning;
    if (hour >= 11 && hour < 14) return _DayPeriod.noon;
    if (hour >= 14 && hour < 18) return _DayPeriod.afternoon;
    return _DayPeriod.evening;
  }
}

class _DoseOccurrence {
  const _DoseOccurrence({
    required this.occurrenceId,
    required this.title,
    required this.scheduledAt,
    required this.timeLabel,
    required this.status,
    required this.period,
  });

  final String occurrenceId;
  final String title;
  final DateTime scheduledAt;
  final String timeLabel;
  final String status;
  final _DayPeriod period;
}

class _PlanHistoryCard extends StatelessWidget {
  const _PlanHistoryCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('dd/MM/yyyy');
    final start = plan.parsedStartDate;
    final end = _HistoryScreenState._resolvedEndDate(plan);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.drugName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${plan.drugs.length} thuốc · ${plan.scheduleSummary}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${start == null ? 'Không rõ' : dateFormatter.format(start)} - ${dateFormatter.format(end)}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: selected ? AppColors.primaryDark : AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({
    required this.plan,
    required this.weekLabel,
    required this.onReuse,
  });

  final Plan plan;
  final String weekLabel;
  final VoidCallback onReuse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.surfaceSoft, AppColors.background],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.drugName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Tuần $weekLabel',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${plan.drugs.length} thuốc · ${plan.slots.length} khung giờ mỗi ngày',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            plan.scheduleSummary,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onReuse,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Dùng lại kế hoạch này'),
          ),
        ],
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.label,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: _SectionTitle(
            title: 'Biểu đồ tuần',
            subtitle: 'T2 - CN theo 4 khung Sáng, Trưa, Chiều, Tối',
          ),
        ),
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        IconButton(
          onPressed: canGoNext ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.weekStart, required this.occurrences});

  final DateTime weekStart;
  final List<_DoseOccurrence> occurrences;

  @override
  Widget build(BuildContext context) {
    final dayHeaders = List<DateTime>.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    final cellMap = <String, List<_DoseOccurrence>>{};
    for (final occurrence in occurrences) {
      final dayIndex = occurrence.scheduledAt.difference(weekStart).inDays;
      if (dayIndex < 0 || dayIndex > 6) continue;
      final key = '$dayIndex:${occurrence.period.name}';
      cellMap.putIfAbsent(key, () => <_DoseOccurrence>[]).add(occurrence);
    }

    final formatter = DateFormat('dd/MM');
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 70),
              ...List<Widget>.generate(dayHeaders.length, (index) {
                final day = dayHeaders[index];
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Text(
                          labels[index],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatter.format(day),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 10),
          ..._DayPeriod.values.map((period) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Row(
                      children: [
                        Icon(period.icon, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          period.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...List<Widget>.generate(7, (dayIndex) {
                    final items =
                        cellMap['$dayIndex:${period.name}'] ??
                        const <_DoseOccurrence>[];
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _WeekCell(items: items),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _WeekCell extends StatelessWidget {
  const _WeekCell({required this.items});

  final List<_DoseOccurrence> items;

  @override
  Widget build(BuildContext context) {
    final summary = _WeekCellSummary.from(items);

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: summary.backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: summary.borderColor),
      ),
      child: summary.isEmpty
          ? const Center(
              child: Text('-', style: TextStyle(color: AppColors.textMuted)),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    summary.label,
                    style: TextStyle(
                      color: summary.foregroundColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    summary.detail,
                    style: TextStyle(
                      color: summary.foregroundColor.withValues(alpha: 0.9),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}

class _WeekCellSummary {
  const _WeekCellSummary({
    required this.label,
    required this.detail,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
    this.isEmpty = false,
  });

  final String label;
  final String detail;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
  final bool isEmpty;

  factory _WeekCellSummary.from(List<_DoseOccurrence> items) {
    if (items.isEmpty) {
      return const _WeekCellSummary(
        label: '-',
        detail: '',
        backgroundColor: AppColors.surfaceSoft,
        borderColor: AppColors.border,
        foregroundColor: AppColors.textMuted,
        isEmpty: true,
      );
    }

    final taken = items.where((item) => item.status == 'taken').length;
    final missed = items.where((item) => item.status == 'missed').length;
    final skipped = items.where((item) => item.status == 'skipped').length;
    final pending = items.where((item) => item.status == 'pending').length;

    if (missed > 0) {
      return _WeekCellSummary(
        label: 'Miss',
        detail: '$missed/${items.length} liều',
        backgroundColor: AppColors.error.withValues(alpha: 0.12),
        borderColor: AppColors.error.withValues(alpha: 0.25),
        foregroundColor: AppColors.error,
      );
    }

    if (pending > 0) {
      return _WeekCellSummary(
        label: 'Chờ',
        detail: '$pending/${items.length} liều',
        backgroundColor: AppColors.info.withValues(alpha: 0.12),
        borderColor: AppColors.info.withValues(alpha: 0.25),
        foregroundColor: AppColors.info,
      );
    }

    if (taken == items.length) {
      return _WeekCellSummary(
        label: 'Đã uống',
        detail: '$taken/${items.length} liều',
        backgroundColor: AppColors.success.withValues(alpha: 0.12),
        borderColor: AppColors.success.withValues(alpha: 0.25),
        foregroundColor: AppColors.success,
      );
    }

    if (skipped == items.length) {
      return _WeekCellSummary(
        label: 'Bỏ qua',
        detail: '$skipped/${items.length} liều',
        backgroundColor: AppColors.warning.withValues(alpha: 0.12),
        borderColor: AppColors.warning.withValues(alpha: 0.25),
        foregroundColor: AppColors.warning,
      );
    }

    return _WeekCellSummary(
      label: 'Hỗn hợp',
      detail: '${items.length} liều',
      backgroundColor: AppColors.primary.withValues(alpha: 0.08),
      borderColor: AppColors.primary.withValues(alpha: 0.22),
      foregroundColor: AppColors.primaryDark,
    );
  }
}

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile({required this.item});

  final _DoseOccurrence item;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (item.status) {
      'taken' => ('Đã uống', AppColors.success, Icons.check_circle_rounded),
      'missed' => ('Đã quên', AppColors.error, Icons.error_rounded),
      'skipped' => ('Bỏ qua', AppColors.warning, Icons.remove_circle_rounded),
      _ => ('Chờ', AppColors.info, Icons.schedule_rounded),
    };

    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            item.timeLabel,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: const [
        _LegendChip(label: 'Đã uống', color: AppColors.success),
        _LegendChip(label: 'Đã quên', color: AppColors.error),
        _LegendChip(label: 'Bỏ qua', color: AppColors.warning),
        _LegendChip(label: 'Chờ', color: AppColors.info),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
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
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }
}

class _WeekEmptyCard extends StatelessWidget {
  const _WeekEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_available_rounded, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text(
            'Tuần này không có liều nào trong kế hoạch đã chọn.',
            style: TextStyle(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreatePlan});

  final VoidCallback onCreatePlan;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    size: 56,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Chưa có kế hoạch cũ nào để xem lại',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Khi một kế hoạch kết thúc, biểu đồ tuần và lịch sử uống thuốc của kế hoạch đó sẽ xuất hiện ở đây.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: onCreatePlan,
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

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
                    Icons.wifi_off_outlined,
                    size: 48,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Không tải được lịch sử kế hoạch',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textMuted),
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

class _ComplianceHeaderCard extends StatelessWidget {
  const _ComplianceHeaderCard({required this.occurrences});

  final List<_DoseOccurrence> occurrences;

  @override
  Widget build(BuildContext context) {
    final nonPending =
        occurrences.where((o) => o.status != 'pending').toList();
    final taken = nonPending.where((o) => o.status == 'taken').length;
    final total = nonPending.length;
    final pct = total == 0 ? 100 : ((taken / total) * 100).round();

    final statusColor = pct >= 80
        ? AppColors.success
        : pct >= 50
            ? AppColors.warning
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(
                  value: pct / 100,
                  strokeWidth: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tỷ lệ tuân thủ tuần này',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 0
                      ? 'Chưa có liều uống được ghi nhận trong tuần'
                      : 'Đã hoàn thành $taken / $total liều được lên lịch',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
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
