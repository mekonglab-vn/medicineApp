import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:medicine_app/core/session/current_user_store.dart';
import 'package:medicine_app/core/theme/app_theme.dart';
import 'package:medicine_app/features/create_plan/data/offline_dose_queue.dart';
import 'package:medicine_app/features/create_plan/domain/plan.dart';
import 'package:medicine_app/features/home/data/plan_notifier.dart';
import 'package:medicine_app/features/home/data/today_schedule_notifier.dart';
import 'package:medicine_app/features/home/domain/today_schedule.dart';
import 'package:medicine_app/features/home/presentation/home_screen.dart';
import 'package:medicine_app/l10n/app_localizations.dart';

class _FakePlanNotifier extends PlanNotifier {
  _FakePlanNotifier(this.stateValue);

  final PlansState stateValue;

  @override
  Future<PlansState> build() async => stateValue;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> syncInBackground() async {}

  @override
  Future<void> ensureNotificationsSynced({
    bool force = false,
    String reason = 'plan_notifier_ensure',
  }) async {}
}

class _FakeTodayScheduleNotifier extends TodayScheduleNotifier {
  _FakeTodayScheduleNotifier(this.schedule);

  final TodaySchedule schedule;

  @override
  Future<TodaySchedule> build() async => schedule;

  @override
  Future<void> refresh() async {}

  @override
  Future<int> flushOfflineQueue() async => 0;
}

class _FakeOfflineDoseQueue extends OfflineDoseQueue {
  _FakeOfflineDoseQueue(this.pending) : super(Dio(), CurrentUserStore());

  final int pending;

  @override
  Future<int> pendingCount() async => pending;
}

Widget _buildHomeApp({
  required PlansState plansState,
  required TodaySchedule schedule,
  int pendingCount = 0,
  Size size = const Size(390, 844),
}) {
  return ProviderScope(
    overrides: [
      planNotifierProvider.overrideWith(() => _FakePlanNotifier(plansState)),
      todayScheduleNotifierProvider.overrideWith(
        () => _FakeTodayScheduleNotifier(schedule),
      ),
      offlineDoseQueueProvider.overrideWithValue(
        _FakeOfflineDoseQueue(pendingCount),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: const Locale('vi'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context).copyWith(size: size);
        return MediaQuery(data: mediaQuery, child: child ?? const SizedBox());
      },
      home: const HomeScreen(),
    ),
  );
}

Plan _buildPlan() {
  return Plan(
    id: 'plan-1',
    title: 'Kế hoạch điều trị kéo dài rất rất rất dài để kiểm tra cắt chữ',
    drugs: const [PlanMedication(id: 'd1', drugName: 'Paracetamol 500mg')],
    slots: const [
      PlanSlot(
        id: 'slot-1',
        time: '07:00',
        items: [PlanSlotMedication(drugName: 'Paracetamol 500mg', pills: 1)],
      ),
    ],
    totalDays: 7,
    startDate: '2026-04-12',
    isActive: true,
  );
}

TodaySchedule _buildEmptySchedule() {
  return const TodaySchedule.empty();
}

TodaySchedule _buildDoseSchedule() {
  final dose = TodayDose(
    occurrenceId: 'occ-1',
    planId: 'plan-1',
    title: 'Buổi sáng với tiêu đề rất rất dài để kiểm tra layout',
    drugName: 'Buổi sáng',
    time: '07:00',
    scheduledTime: DateTime.now().toUtc().toIso8601String(),
    status: 'pending',
    medications: const [
      TodayDoseMedication(drugName: 'Aspirin Forte', pills: 2),
      TodayDoseMedication(drugName: 'Cetirizine', pills: 1),
      TodayDoseMedication(drugName: 'Ibuprofen', pills: 3),
    ],
  );

  return TodaySchedule(
    date: '2026-04-12',
    doses: [dose],
    summary: const TodaySummary(
      total: 0,
      taken: 0,
      pending: 0,
      skipped: 0,
      missed: 0,
    ),
  ).recount();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('vi_VN');
  });

  testWidgets('renders Vietnamese date and empty-state actions', (
    tester,
  ) async {
    final expectedDate = DateFormat(
      'd MMMM, yyyy',
      'vi_VN',
    ).format(DateTime.now());
    final plan = _buildPlan();

    await tester.pumpWidget(
      _buildHomeApp(
        plansState: PlansState(plans: [plan], loadedAt: DateTime.now()),
        schedule: _buildEmptySchedule(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(expectedDate), findsOneWidget);
    expect(find.text('Hôm nay không có liều uống nào.'), findsOneWidget);
    expect(find.text('Quét đơn'), findsWidgets);
    expect(find.text('Tạo kế hoạch'), findsOneWidget);
    expect(find.text('Xem kế hoạch'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('clamps long texts and adapts quick actions on narrow screens', (
    tester,
  ) async {
    final plan = _buildPlan();
    final schedule = _buildDoseSchedule();

    await tester.pumpWidget(
      _buildHomeApp(
        plansState: PlansState(plans: [plan], loadedAt: DateTime.now()),
        schedule: schedule,
        size: const Size(320, 844),
      ),
    );
    await tester.pumpAndSettle();

    final doseTitle = tester.widget<Text>(
      find.text(schedule.doses.first.primaryTitle).first,
    );
    expect(doseTitle.maxLines, 2);
    expect(doseTitle.overflow, TextOverflow.ellipsis);

    const summaryText = 'Aspirin Forte, Cetirizine và 1 thuốc khác • 6 viên';
    final summary = tester.widget<Text>(find.text(summaryText).first);
    expect(summary.maxLines, 2);
    expect(summary.overflow, TextOverflow.ellipsis);

    expect(find.text('Quét đơn'), findsWidgets);
    expect(find.text('Nhập tay'), findsWidgets);
    expect(find.text('Tra cứu'), findsWidgets);

    expect(tester.takeException(), isNull);
  });
}
