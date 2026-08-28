import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/features/drug/data/drug_repository.dart';
import 'package:medicine_app/features/lookup/data/drug_interaction_repository.dart';
import 'package:medicine_app/features/lookup/presentation/lookup_screen.dart';
import 'package:medicine_app/l10n/app_localizations.dart';

Widget _buildTestApp({
  DrugRepository? drugRepository,
  DrugInteractionRepository? interactionRepository,
}) {
  return ProviderScope(
    overrides: [
      if (drugRepository != null)
        drugRepositoryProvider.overrideWithValue(drugRepository),
      if (interactionRepository != null)
        drugInteractionRepositoryProvider.overrideWithValue(
          interactionRepository,
        ),
    ],
    child: MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const LookupScreen(),
    ),
  );
}

class _FakeDrugRepository extends DrugRepository {
  _FakeDrugRepository() : super(Dio());

  @override
  Future<DrugSearchPage> search(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    final normalized = query.trim().toLowerCase();
    final items = <DrugSearchItem>[
      if (normalized.contains('war'))
        const DrugSearchItem(
          name: 'Warfarin Test',
          score: 0.98,
          activeIngredient: 'warfarin',
        ),
      if (normalized.contains('asp'))
        const DrugSearchItem(
          name: 'Aspirin Test',
          score: 0.96,
          activeIngredient: 'aspirin',
        ),
    ];

    return DrugSearchPage(
      items: items,
      total: items.length,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<DrugDetails> getByName(String name) async {
    return DrugDetails(name: name, raw: const {'tenThuoc': 'Fake drug'});
  }
}

class _FakeInteractionRepository extends DrugInteractionRepository {
  _FakeInteractionRepository() : super(Dio());

  @override
  Future<InteractionCheckResult> checkByDrugs(List<String> drugNames) async {
    return const InteractionCheckResult(
      hasInteractions: true,
      totalInteractions: 1,
      highestSeverity: 'major',
      severitySummary: {
        'contraindicated': 0,
        'major': 1,
        'moderate': 0,
        'minor': 0,
        'caution': 0,
        'unknown': 0,
      },
      groups: [],
      interactions: [
        InteractionItem(
          drugA: 'Warfarin Test',
          drugB: 'Aspirin Test',
          ingredientA: 'warfarin',
          ingredientB: 'aspirin',
          severity: 'major',
          severityOriginal: 'Nghiêm trọng',
          warning: 'Tăng nguy cơ chảy máu',
        ),
      ],
      message: 'Đã tìm thấy tương tác thuốc.',
    );
  }

  @override
  Future<List<ActiveIngredientSuggestion>> searchActiveIngredients(
    String keyword,
  ) async {
    final normalized = keyword.trim().toLowerCase();
    return [
      if (normalized.contains('war'))
        const ActiveIngredientSuggestion(name: 'warfarin'),
      if (normalized.contains('asp'))
        const ActiveIngredientSuggestion(name: 'aspirin'),
    ];
  }

  @override
  Future<InteractionCheckResult> checkByActiveIngredients(
    List<String> activeIngredients,
  ) async {
    return const InteractionCheckResult(
      hasInteractions: true,
      totalInteractions: 1,
      highestSeverity: 'moderate',
      severitySummary: {
        'contraindicated': 0,
        'major': 0,
        'moderate': 1,
        'minor': 0,
        'caution': 0,
        'unknown': 0,
      },
      groups: [
        InteractionGroup(
          severity: 'moderate',
          severityOriginal: 'Trung bình',
          count: 1,
          interactions: [
            InteractionItem(
              drugA: '',
              drugB: '',
              ingredientA: 'warfarin',
              ingredientB: 'aspirin',
              severity: 'moderate',
              severityOriginal: 'Trung bình',
              warning: 'Theo dõi INR khi dùng kéo dài.',
            ),
          ],
        ),
      ],
      interactions: [
        InteractionItem(
          drugA: '',
          drugB: '',
          ingredientA: 'warfarin',
          ingredientB: 'aspirin',
          severity: 'moderate',
          severityOriginal: 'Trung bình',
          warning: 'Theo dõi INR khi dùng kéo dài.',
        ),
      ],
      message: 'Tìm thấy 1 tương tác',
    );
  }

  @override
  Future<InteractionCheckResult> getByActiveIngredient(
    String ingredientName,
  ) async {
    return const InteractionCheckResult(
      hasInteractions: true,
      totalInteractions: 1,
      highestSeverity: 'unknown',
      severitySummary: {
        'contraindicated': 0,
        'major': 0,
        'moderate': 0,
        'minor': 0,
        'caution': 0,
        'unknown': 1,
      },
      groups: [],
      interactions: [
        InteractionItem(
          drugA: '',
          drugB: '',
          ingredientA: 'Levocetirizine',
          ingredientB: 'Theophylline',
          severity: 'unknown',
          severityOriginal: 'Không xác định',
          warning: 'Giảm nhẹ độ thanh thải',
        ),
      ],
      message: 'Tìm thấy 1 tương tác',
    );
  }
}

void main() {
  testWidgets('renders lookup tab sections', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Tra cứu'), findsWidgets);
    expect(find.text('Thuốc'), findsOneWidget);
    expect(find.text('Tương tác'), findsOneWidget);
    expect(find.text('Hoạt chất'), findsOneWidget);
    expect(find.text('Tra cứu thuốc'), findsOneWidget);
  });

  testWidgets('shows validation message when checking interactions too early', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tương tác'));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra tương tác theo thuốc'), findsOneWidget);

    await tester.tap(find.text('Kiểm tra tương tác'));
    await tester.pumpAndSettle();

    expect(find.text('Cần chọn ít nhất 2 thuốc để kiểm tra.'), findsOneWidget);
  });

  testWidgets('renders successful interaction-by-drug result', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        drugRepository: _FakeDrugRepository(),
        interactionRepository: _FakeInteractionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tương tác'));
    await tester.pumpAndSettle();

    final interactionField = find.byType(TextField).first;
    await tester.enterText(interactionField, 'war');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warfarin Test'));
    await tester.pumpAndSettle();

    await tester.enterText(interactionField, 'asp');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aspirin Test'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kiểm tra tương tác').last);
    await tester.pumpAndSettle();

    expect(find.text('Kết quả tương tác theo thuốc'), findsOneWidget);
    expect(find.text('Warfarin Test + Aspirin Test'), findsOneWidget);
    expect(find.text('Tăng nguy cơ chảy máu'), findsOneWidget);
  });

  testWidgets('renders successful interaction-by-ingredient result', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(interactionRepository: _FakeInteractionRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hoạt chất'));
    await tester.pumpAndSettle();

    final ingredientField = find.byType(TextField).first;
    await tester.enterText(ingredientField, 'war');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('warfarin'));
    await tester.pumpAndSettle();

    await tester.enterText(ingredientField, 'asp');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('aspirin'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kiểm tra theo hoạt chất').last);
    await tester.pumpAndSettle();

    expect(find.text('Kết quả theo danh sách hoạt chất'), findsOneWidget);
    expect(find.text('warfarin + aspirin'), findsOneWidget);
    expect(find.text('Theo dõi INR khi dùng kéo dài.'), findsOneWidget);
  });
}
