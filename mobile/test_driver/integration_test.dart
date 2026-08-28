import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, screenshotBytes, [args]) async {
      final dir = Directory('build/integration_test_screenshots/2026-04-13');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File('${dir.path}/$name.png');
      await file.writeAsBytes(screenshotBytes);
      return true;
    },
  );
}
