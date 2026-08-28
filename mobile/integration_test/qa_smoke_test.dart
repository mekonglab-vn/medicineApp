import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:medicine_app/main.dart' as app;

class _QaUser {
  const _QaUser({required this.email, required this.password});

  final String email;
  final String password;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await binding.convertFlutterSurfaceToImage();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 4));
  }

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 300));
      if (finder.evaluate().isNotEmpty) {
        await tester.pumpAndSettle(const Duration(seconds: 1));
        return;
      }
    }
    expect(finder, findsWidgets);
  }

  Future<void> launchToLogin(WidgetTester tester) async {
    await pumpApp(tester);
    await waitFor(tester, find.byType(TextField));
  }

  Future<void> screenshot(String name) async {
    await binding.takeScreenshot(name);
  }

  Future<Map<String, dynamic>> apiJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:3001/api$path'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'API $method $path failed: ${response.statusCode} $text',
        );
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> loginForApi(_QaUser user) async {
    final response = await apiJson(
      'POST',
      '/auth/login',
      body: {'email': user.email, 'password': user.password},
    );
    return (response['data'] as Map<String, dynamic>)['accessToken'] as String;
  }

  Future<void> deactivatePlanByTitle(_QaUser user, String title) async {
    final token = await loginForApi(user);
    final activeResponse = await apiJson(
      'GET',
      '/plans?active=true',
      token: token,
    );
    final activePlans = (activeResponse['data'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final activeMatch = activePlans.where(
      (item) => (item['title'] as String?) == title,
    );
    if (activeMatch.isNotEmpty) {
      await apiJson(
        'DELETE',
        '/plans/${activeMatch.first['id']}',
        token: token,
      );
      return;
    }

    final allResponse = await apiJson(
      'GET',
      '/plans?active=false',
      token: token,
    );
    final allPlans = (allResponse['data'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final existing = allPlans.where(
      (item) => (item['title'] as String?) == title,
    );
    if (existing.isEmpty) {
      throw StateError('Plan not found: $title');
    }
    final isActive = existing.first['is_active'] as bool? ?? true;
    if (!isActive) {
      return;
    }

    await apiJson('DELETE', '/plans/${existing.first['id']}', token: token);
  }

  Future<void> openRegister(WidgetTester tester) async {
    final registerLink = find.textContaining('Đăng ký').last;
    await tester.ensureVisible(registerLink);
    await tester.tap(registerLink, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> openLogin(WidgetTester tester) async {
    final loginLink = find.textContaining('Đăng nhập').last;
    await tester.ensureVisible(loginLink);
    await tester.tap(loginLink, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  _QaUser userFromEnv(String prefix) {
    final email = switch (prefix) {
      'QA_EMPTY' => const String.fromEnvironment('QA_EMPTY_EMAIL'),
      'QA_FULL' => const String.fromEnvironment('QA_FULL_EMAIL'),
      _ => '',
    };
    final password = switch (prefix) {
      'QA_EMPTY' => const String.fromEnvironment('QA_EMPTY_PASSWORD'),
      'QA_FULL' => const String.fromEnvironment('QA_FULL_PASSWORD'),
      _ => '',
    };
    if (email.isEmpty || password.isEmpty) {
      throw StateError(
        'Missing dart-define for ${prefix}_EMAIL/${prefix}_PASSWORD',
      );
    }
    return _QaUser(email: email, password: password);
  }

  Future<void> loginWithUi(WidgetTester tester, _QaUser user) async {
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));
    await tester.enterText(textFields.at(0), user.email);
    await tester.enterText(textFields.at(1), user.password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Đăng nhập'));
    await tester.pumpAndSettle(const Duration(seconds: 6));
  }

  Future<void> logoutFromSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Cài đặt'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Đăng xuất'));
    await tester.pumpAndSettle(const Duration(seconds: 4));
  }

  Future<void> goToShellTab(WidgetTester tester, String label) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      final tab = find.text(label);
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.last, warnIfMissed: false);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        return;
      }

      final back = find.byIcon(Icons.arrow_back);
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first, warnIfMissed: false);
        await tester.pumpAndSettle(const Duration(seconds: 2));
        continue;
      }

      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text(label), findsWidgets);
  }

  testWidgets('QA smoke empty user shell states', (tester) async {
    final emptyUser = userFromEnv('QA_EMPTY');

    await launchToLogin(tester);
    expect(find.text('Quản lý đơn thuốc thông minh'), findsOneWidget);
    await screenshot('02_login_default');

    await openRegister(tester);
    expect(find.text('Tạo tài khoản'), findsOneWidget);
    await screenshot('04_register_default');

    await openLogin(tester);

    await loginWithUi(tester, emptyUser);
    expect(find.textContaining('Bắt đầu quản lý thuốc'), findsOneWidget);
    await screenshot('05_home_empty');

    await goToShellTab(tester, 'Kế hoạch');
    await screenshot('09_plans_list_empty');

    await goToShellTab(tester, 'Lịch sử');
    expect(find.textContaining('Chưa có kế hoạch cũ nào'), findsOneWidget);
    await screenshot('13_history_empty');

    await logoutFromSettings(tester);
    expect(find.text('Uống thuốc'), findsOneWidget);
  });

  testWidgets('QA smoke populated user shell states', (tester) async {
    final populatedUser = userFromEnv('QA_FULL');

    await launchToLogin(tester);

    await loginWithUi(tester, populatedUser);
    await waitFor(tester, find.text('Trang chủ'));
    await screenshot('06_home_due');

    if (find.text('Đã uống').evaluate().isNotEmpty) {
      await tester.tap(find.text('Đã uống').first);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      await screenshot('06_home_after_taken');
    }

    await goToShellTab(tester, 'Kế hoạch');
    expect(find.text('Paracetamol demo'), findsOneWidget);
    await screenshot('09_plans_list');

    await tester.tap(find.text('Paracetamol demo').first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Chỉnh sửa thuốc và lịch'), findsWidgets);
    await screenshot('10_plan_detail_single');

    await deactivatePlanByTitle(populatedUser, 'Paracetamol demo');

    await goToShellTab(tester, 'Lịch sử');
    await waitFor(tester, find.text('Kế hoạch cũ'));
    await screenshot('14_history_week_grid');

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Cài đặt'), findsOneWidget);
    await screenshot('23_settings');
  });

  testWidgets('QA smoke plan edit flow', (tester) async {
    final populatedUser = userFromEnv('QA_FULL');

    await launchToLogin(tester);

    await loginWithUi(tester, populatedUser);
    await waitFor(tester, find.text('Trang chủ'));

    await goToShellTab(tester, 'Kế hoạch');
    final primaryPlan = find.text('Paracetamol demo');
    final fallbackPlan = find.text('Vitamin C cu');
    final planFinder = primaryPlan.evaluate().isNotEmpty
        ? primaryPlan.first
        : fallbackPlan.first;

    await tester.tap(planFinder, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await waitFor(tester, find.text('Chỉnh sửa thuốc và lịch'));

    await tester.tap(find.text('Chỉnh sửa thuốc và lịch').first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await screenshot('12_plan_edit_drugs');
  });

  testWidgets('QA smoke create reuse flow', (tester) async {
    final populatedUser = userFromEnv('QA_FULL');

    await launchToLogin(tester);

    await loginWithUi(tester, populatedUser);
    await waitFor(tester, find.text('Trang chủ'));

    await goToShellTab(tester, 'Kế hoạch');

    final createPlanFab = find.byType(FloatingActionButton);
    expect(createPlanFab, findsOneWidget);
    await tester.ensureVisible(createPlanFab);
    await tester.tap(createPlanFab.first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await waitFor(tester, find.textContaining('Quét'));
    await screenshot('15_create_plan_options');

    await tester.tap(find.textContaining('Dùng lại').first);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining('Dùng lại kế hoạch cũ'), findsOneWidget);
    await screenshot('18_reuse_old_plan');
  });

  testWidgets('QA smoke drug lookup flow', (tester) async {
    final emptyUser = userFromEnv('QA_EMPTY');

    await launchToLogin(tester);

    await loginWithUi(tester, emptyUser);
    await waitFor(tester, find.textContaining('Bắt đầu quản lý thuốc'));

    final drugLookup = find.textContaining('Tra cứu thuốc');
    await tester.ensureVisible(drugLookup.first);
    await tester.tap(drugLookup.first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Tra cứu'), findsWidgets);
    expect(find.text('Thuốc'), findsOneWidget);
    expect(find.text('Tương tác'), findsOneWidget);
    expect(find.text('Hoạt chất'), findsOneWidget);
    await screenshot('21_drug_search_default');

    final drugField = find.byType(TextField).first;
    await tester.enterText(drugField, 'paracetamol');
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await screenshot('21_drug_search_results');

    await tester.tap(find.text('Tương tác'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Kiểm tra tương tác'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Cần chọn ít nhất 2 thuốc để kiểm tra.'), findsOneWidget);
    await screenshot('22_lookup_interactions_validation');

    final interactionField = find.byType(TextField).first;
    await tester.enterText(interactionField, 'aviranz');
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await waitFor(tester, find.textContaining('Aviranz'));
    await tester.tap(find.textContaining('Aviranz').first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(interactionField, 'adefovir');
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await waitFor(tester, find.textContaining('Adefovir'));
    await tester.tap(
      find.textContaining('Adefovir').first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await screenshot('22_lookup_interactions_selected');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Kiểm tra tương tác'));
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await waitFor(tester, find.text('Kết quả tương tác theo thuốc'));
    await screenshot('22_lookup_interactions_success');

    await tester.tap(find.text('Hoạt chất'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Tra cứu hoạt chất'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Nhập ít nhất 2 ký tự hoạt chất.'), findsOneWidget);
    await screenshot('23_lookup_ingredient_validation');

    final ingredientField = find.byType(TextField).first;
    await tester.enterText(ingredientField, 'efa');
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await waitFor(tester, find.textContaining('efavirenz'));
    await tester.tap(
      find.textContaining('efavirenz').first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.enterText(ingredientField, 'adefovir');
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await waitFor(tester, find.textContaining('adefovir'));
    await tester.tap(
      find.textContaining('adefovir').first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await screenshot('23_lookup_ingredients_selected');

    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Kiểm tra theo hoạt chất'),
    );
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await waitFor(tester, find.text('Kết quả theo danh sách hoạt chất'));
    await screenshot('23_lookup_ingredients_success');

    final singleIngredientField = find.byType(TextField).at(1);
    await tester.enterText(singleIngredientField, 'Levocetirizine');
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Tra cứu hoạt chất'));
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await waitFor(tester, find.text('Kết quả theo một hoạt chất'));
    await screenshot('24_lookup_single_ingredient_success');

    await tester.tap(find.text('Danh mục hoạt chất'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    await waitFor(tester, find.text('Danh mục hoạt chất'));
    await screenshot('25_lookup_ingredient_catalog');
  });
}
