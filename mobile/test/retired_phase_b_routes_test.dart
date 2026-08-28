import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/core/router/app_router.dart';
import 'package:medicine_app/l10n/app_localizations.dart';

void main() {
  for (final route in ['/pill-verify', '/pill-reference/enroll']) {
    testWidgets('$route reaches the unknown-route fallback', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(authStateProvider.notifier).setAuthenticated();

      final router = container.read(routerProvider);
      addTearDown(router.dispose);
      router.go(route);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('vi'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trang không tìm thấy'), findsWidgets);
      expect(find.text('Xác minh viên thuốc'), findsNothing);
      expect(find.text('Chụp mẫu viên thuốc'), findsNothing);
    });
  }
}
