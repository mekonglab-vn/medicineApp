import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Primary Color (MÀU CHỦ ĐẠO GIỮ NGUYÊN)
  static const Color primary = Color(0xFF43C7C8);
  static const Color primaryDark = Color(0xFF1B8B8D);
  static const Color primaryLight = Color(0xFFD3F6F5);
  static const Color accent = Color(0xFF6BE5E6);

  // Background & Surfaces (Soft Mint Cyan Slate Palette)
  static const Color background = Color(0xFFF3FAFA);
  static const Color surface = Colors.white;
  static const Color surfaceHigh = Color(0xFFDDF0F0);
  static const Color surfaceSoft = Color(0xFFEEF8F8);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFCFE8E8);

  // Typography (Slate Teal Harmonized Text Palette)
  static const Color textPrimary = Color(0xFF0F2B2D);
  static const Color textSecondary = Color(0xFF3B686A);
  static const Color textMuted = Color(0xFF6F999B);

  // Health Status & Semantics (Chuẩn y tế: Phân biệt rõ ràng Trạng thái & Mức độ khẩn cấp)
  static const Color success = Color(0xFF10B981); // Emerald Green (Đã uống / Hoàn thành)
  static const Color warning = Color(0xFFF59E0B); // Amber Gold (Chú ý / Bỏ qua)
  static const Color error = Color(0xFFEF4444);   // Rose Red (Bỏ lỡ / Nguy hiểm / Lỗi)
  static const Color info = Color(0xFF3B82F6);    // Royal Blue (Thông tin hệ thống)

  static const Color taken = success;
  static const Color missed = error;
  static const Color skipped = warning;
  static const Color infoCard = Color(0xFFEFF6FF);

  // Drug Interaction Severity Levels (Các cấp độ tương tác thuốc chuẩn dải màu Teal #43C7C8)
  static const Color severityCriticalBg = Color(0xFFD2EFEB);
  static const Color severityCriticalFg = Color(0xFF094345);

  static const Color severityHighBg = Color(0xFFDCF4F2);
  static const Color severityHighFg = Color(0xFF136E70);

  static const Color severityModerateBg = Color(0xFFE5FAF8);
  static const Color severityModerateFg = Color(0xFF1F989A);

  static const Color severityLowBg = Color(0xFFF0FCFB);
  static const Color severityLowFg = Color(0xFF43C7C8);

  static const Color severityInfoBg = Color(0xFFF4FCFC);
  static const Color severityInfoFg = Color(0xFF2BB9BB);
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  static const double radiusSm = 10.0;
  static const double radiusMd = 16.0;
  static const double radiusLg = 20.0;
  static const double radiusXl = 24.0;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: lg, vertical: md);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primaryDark,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.card,
      dividerColor: AppColors.border,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunito(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: AppColors.primaryDark,
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceHigh,
          minimumSize: const Size(double.infinity, 54),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: AppColors.primaryDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
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
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.border),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceSoft,
        selectedColor: AppColors.primary,
        disabledColor: AppColors.surfaceHigh,
        labelStyle: const TextStyle(color: AppColors.textPrimary),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.primaryDark),
    );
  }
}
