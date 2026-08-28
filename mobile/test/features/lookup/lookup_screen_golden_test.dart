import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/core/theme/app_theme.dart';
import 'package:medicine_app/features/drug/data/drug_repository.dart';
import 'package:medicine_app/features/lookup/data/drug_interaction_repository.dart';
import 'package:medicine_app/features/lookup/presentation/active_ingredient_catalog_screen.dart';
import 'package:medicine_app/features/lookup/presentation/active_ingredient_interactions_screen.dart';
import 'package:medicine_app/features/lookup/presentation/lookup_screen.dart';
import 'package:medicine_app/l10n/app_localizations.dart';

Widget _buildApp(
  Widget child, {
  DrugRepository? drugRepository,
  DrugInteractionRepository? interactionRepository,
}) {
  final theme = ThemeData.light(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primaryDark,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primaryDark, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 54),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        side: const BorderSide(color: AppColors.primaryDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return AppColors.textSecondary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.surface;
        }),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceSoft,
      labelStyle: const TextStyle(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
  );

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
      theme: theme,
      locale: const Locale('vi'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
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
      if (normalized.contains('avir'))
        const DrugSearchItem(
          name: 'Aviranz tablets 600mg',
          score: 0.98,
          activeIngredient: 'efavirenz',
        ),
      if (normalized.contains('ade'))
        const DrugSearchItem(
          name: 'Adefovir 10 mg',
          score: 0.95,
          activeIngredient: 'adefovir dipivoxil',
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
      highestSeverity: 'contraindicated',
      severitySummary: {
        'contraindicated': 1,
        'major': 0,
        'moderate': 0,
        'minor': 0,
        'caution': 0,
        'unknown': 0,
      },
      groups: [],
      interactions: [
        InteractionItem(
          drugA: 'Aviranz tablets 600mg',
          drugB: 'Adefovir 10 mg',
          ingredientA: 'efavirenz',
          ingredientB: 'adefovir dipivoxil',
          severity: 'contraindicated',
          severityOriginal: 'Chống chỉ định',
          warning:
              'Không nên sử dụng đồng thời Efavirenz với Adefovir dipivoxil.',
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
      if (normalized.contains('efa'))
        const ActiveIngredientSuggestion(name: 'efavirenz'),
      if (normalized.contains('ade'))
        const ActiveIngredientSuggestion(name: 'adefovir dipivoxil'),
    ];
  }

  @override
  Future<ActiveIngredientCatalogPage> listActiveIngredients(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    return const ActiveIngredientCatalogPage(
      items: [
        ActiveIngredientCatalogItem(name: 'efavirenz', interactionCount: 12),
        ActiveIngredientCatalogItem(
          name: 'adefovir dipivoxil',
          interactionCount: 8,
        ),
        ActiveIngredientCatalogItem(
          name: 'levocetirizine',
          interactionCount: 4,
        ),
      ],
      total: 3,
      page: 1,
      limit: 20,
    );
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
              ingredientA: 'efavirenz',
              ingredientB: 'adefovir dipivoxil',
              severity: 'moderate',
              severityOriginal: 'Trung bình',
              warning: 'Theo dõi chức năng gan khi phối hợp kéo dài.',
            ),
          ],
        ),
      ],
      interactions: [
        InteractionItem(
          drugA: '',
          drugB: '',
          ingredientA: 'efavirenz',
          ingredientB: 'adefovir dipivoxil',
          severity: 'moderate',
          severityOriginal: 'Trung bình',
          warning: 'Theo dõi chức năng gan khi phối hợp kéo dài.',
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
      groups: [
        InteractionGroup(
          severity: 'unknown',
          severityOriginal: 'Không xác định',
          count: 1,
          interactions: [
            InteractionItem(
              drugA: '',
              drugB: '',
              ingredientA: 'Levocetirizine',
              ingredientB: 'Theophylline',
              severity: 'unknown',
              severityOriginal: 'Không xác định',
              warning: 'Giảm nhẹ độ thanh thải cetirizine.',
            ),
          ],
        ),
      ],
      interactions: [
        InteractionItem(
          drugA: '',
          drugB: '',
          ingredientA: 'Levocetirizine',
          ingredientB: 'Theophylline',
          severity: 'unknown',
          severityOriginal: 'Không xác định',
          warning: 'Giảm nhẹ độ thanh thải cetirizine.',
        ),
      ],
      message: 'Tìm thấy 1 tương tác',
    );
  }
}

void main() {
  testWidgets('golden: interaction lookup success', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _buildApp(
        const LookupScreen(),
        drugRepository: _FakeDrugRepository(),
        interactionRepository: _FakeInteractionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tương tác'));
    await tester.pumpAndSettle();

    final interactionField = find.byType(TextField).first;
    await tester.enterText(interactionField, 'avir');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aviranz tablets 600mg'));
    await tester.pumpAndSettle();

    await tester.enterText(interactionField, 'ade');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adefovir 10 mg'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kiểm tra tương tác').last);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lookup_interactions_success.png'),
    );
  });

  testWidgets('golden: ingredient lookup success', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _buildApp(
        const LookupScreen(),
        interactionRepository: _FakeInteractionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hoạt chất'));
    await tester.pumpAndSettle();

    final ingredientField = find.byType(TextField).first;
    await tester.enterText(ingredientField, 'efa');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('efavirenz'));
    await tester.pumpAndSettle();

    await tester.enterText(ingredientField, 'ade');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('adefovir dipivoxil'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kiểm tra theo hoạt chất').last);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lookup_ingredients_success.png'),
    );
  });

  testWidgets('golden: ingredient catalog', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _buildApp(
        const ActiveIngredientCatalogScreen(),
        interactionRepository: _FakeInteractionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lookup_ingredient_catalog.png'),
    );
  });

  testWidgets('golden: single ingredient detail', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _buildApp(
        const ActiveIngredientInteractionsScreen(
          ingredientName: 'Levocetirizine',
        ),
        interactionRepository: _FakeInteractionRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lookup_single_ingredient_detail.png'),
    );
  });
}
