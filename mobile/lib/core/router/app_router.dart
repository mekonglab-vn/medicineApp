import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../shared/widgets/main_shell.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/create_plan/presentation/create_plan_screen.dart';
import '../../features/create_plan/presentation/scan_camera_screen.dart';
import '../../features/create_plan/presentation/scan_review_screen.dart';
import '../../features/create_plan/presentation/edit_drugs_screen.dart';
import '../../features/create_plan/presentation/set_schedule_screen.dart';
import '../../features/create_plan/presentation/reuse_history_screen.dart';
import '../../features/create_plan/domain/plan.dart';
import '../../features/create_plan/domain/scan_result.dart';
import '../../features/drug/presentation/drug_search_screen.dart';
import '../../features/drug/presentation/drug_detail_screen.dart';
import '../../features/drug/data/drug_repository.dart';
import '../../features/lookup/presentation/lookup_screen.dart';
import '../../features/lookup/presentation/active_ingredient_catalog_screen.dart';
import '../../features/lookup/presentation/active_ingredient_interactions_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/plan/presentation/plan_detail_screen.dart';
import '../../features/plan/presentation/plan_list_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

/// Tri-state auth: loading (cold start) → authenticated / unauthenticated.
enum AuthStatus { loading, authenticated, unauthenticated }

/// Auth state notifier — tracks authentication status.
class AuthStateNotifier extends Notifier<AuthStatus> {
  @override
  AuthStatus build() => AuthStatus.loading;

  void setAuthenticated() => state = AuthStatus.authenticated;
  void setUnauthenticated() => state = AuthStatus.unauthenticated;
}

final authStateProvider = NotifierProvider<AuthStateNotifier, AuthStatus>(
  AuthStateNotifier.new,
);

final routerProvider = Provider<GoRouter>((ref) {
  final authStatus = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/boot',
    errorBuilder: (context, state) => const _RouteFallbackScreen(),
    redirect: (context, state) {
      final onAuthPage =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      final onBoot = state.matchedLocation == '/boot';

      if (authStatus == AuthStatus.loading) {
        return onBoot ? null : '/boot';
      }

      if (authStatus == AuthStatus.unauthenticated) {
        return onAuthPage ? null : '/login';
      }

      if (onBoot || onAuthPage) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/boot', builder: (context, state) => const _BootScreen()),
      // ── Auth (outside bottom nav) ──
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // ── Secondary flows (outside bottom nav) ──
      GoRoute(
        path: '/create',
        builder: (context, state) => const CreatePlanScreen(),
      ),
      GoRoute(
        path: '/create/reuse',
        builder: (context, state) => const ReuseHistoryScreen(),
      ),
      GoRoute(
        path: '/create/scan',
        builder: (context, state) => const ScanCameraScreen(),
      ),
      GoRoute(
        path: '/create/edit',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is PlanEditFlowArgs) {
            return EditDrugsScreen(
              initialDrugs: extra.drugs,
              existingPlan: extra.existingPlan,
            );
          }
          final drugs = extra as List<PlanDrugItem>? ?? [];
          return EditDrugsScreen(initialDrugs: drugs);
        },
      ),
      GoRoute(
        path: '/create/review',
        builder: (context, state) {
          final result = state.extra as ScanResult?;
          return ScanReviewScreen(
            result: result ?? const ScanResult(scanId: '', drugs: []),
          );
        },
      ),
      GoRoute(
        path: '/create/schedule',
        builder: (context, state) {
          final extra = state.extra;
          // Backward-compat: scan path truyền List<PlanDrugItem> trực tiếp.
          // Manual path truyền Map {'drugs': List<PlanDrugItem>, 'source': String}.
          final List<PlanDrugItem> drugs;
          final String source;
          Plan? existingPlan;
          if (extra is List<PlanDrugItem>) {
            drugs = extra;
            source = 'scan';
          } else if (extra is PlanEditFlowArgs) {
            drugs = extra.drugs;
            source = extra.source;
            existingPlan = extra.existingPlan;
          } else if (extra is Map<String, dynamic>) {
            drugs = (extra['drugs'] as List<PlanDrugItem>?) ?? [];
            source = (extra['source'] as String?) ?? 'scan';
            existingPlan = extra['existingPlan'] as Plan?;
          } else {
            drugs = [];
            source = 'scan';
          }
          return SetScheduleScreen(
            drugs: drugs,
            source: source,
            existingPlan: existingPlan,
          );
        },
      ),
      GoRoute(
        path: '/drugs',
        builder: (context, state) => const DrugSearchScreen(),
      ),
      GoRoute(
        path: '/drugs/detail',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final details = extra?['details'];
          return DrugDetailScreen(
            details: details is DrugDetails
                ? details
                : const DrugDetails(name: 'Thông tin thuốc'),
            activeIngredient: extra?['activeIngredient'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/lookup',
        builder: (context, state) => const LookupScreen(),
      ),
      GoRoute(
        path: '/lookup/ingredients',
        builder: (context, state) => const ActiveIngredientCatalogScreen(),
      ),
      GoRoute(
        path: '/lookup/ingredients/:name',
        builder: (context, state) => ActiveIngredientInteractionsScreen(
          ingredientName: Uri.decodeComponent(
            state.pathParameters['name'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // ── Main Shell (Bottom Nav — 3 tabs) ──
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/plans',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PlanListScreen()),
          ),
          GoRoute(
            path: '/plans/:id',
            builder: (context, state) =>
                PlanDetailScreen(planId: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HistoryScreen()),
          ),
          GoRoute(
            path: '/history/scan/:id',
            redirect: (context, state) => '/history',
          ),
        ],
      ),
    ],
  );
});

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _RouteFallbackScreen extends StatelessWidget {
  const _RouteFallbackScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.routeFallbackTitle)),
      body: Center(child: Text(l10n.routeFallbackTitle)),
    );
  }
}
