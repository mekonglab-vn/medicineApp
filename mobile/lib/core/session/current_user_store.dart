import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants.dart';

class CurrentUserStore {
  static const _storage = FlutterSecureStorage();

  Future<String?> getCurrentUserId() async {
    final raw = await _storage.read(key: AppConstants.userKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final userId = parsed['id']?.toString().trim() ?? '';
      if (userId.isEmpty) {
        return null;
      }
      return userId;
    } catch (_) {
      return null;
    }
  }
}

final currentUserStoreProvider = Provider<CurrentUserStore>((ref) {
  return CurrentUserStore();
});
