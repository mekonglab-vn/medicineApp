import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsRepository {
  static const _storage = FlutterSecureStorage();
  static const _reminderKey = 'settings_reminders_enabled';

  Future<bool> getRemindersEnabled() async {
    final raw = await _storage.read(key: _reminderKey);
    return raw != 'false';
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    await _storage.write(key: _reminderKey, value: enabled ? 'true' : 'false');
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});
