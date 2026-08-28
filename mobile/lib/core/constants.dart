import '../l10n/app_localizations.dart';

/// App-wide constants.
class AppConstants {
  AppConstants._();

  static String appTitle(AppLocalizations l10n) => l10n.appTitle;

  // API
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration scanTimeout = Duration(seconds: 60);
  static const int maxFileSizeMB = 10;

  // Auth
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userKey = 'user_data';

  // Local DB
  static const String dbName = 'medicine_app.db';
  static const int dbVersion = 1;
}
