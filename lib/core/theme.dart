import 'package:flutter/material.dart';

/// Shared dark palette for Dramix, evolving the original Anixart reference.
class AppColors {
  static const Color bg = Color(0xFF121212);          // page background
  static const Color surface = Color(0xFF252525);     // pills, search bar, nav
  static const Color surfaceHigh = Color(0xFF2E2E2E); // cards, chips hover
  static const Color outline = Color(0xFF3D3D3D);     // outlined pill borders
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textTertiary = Color(0xFF71717A);
  static const Color accent = Color(0xFF4A4458);      // nav pill / primary soft
  static const Color light = Color(0xFFE0E0E0);       // light primary buttons
  static const Color badgeNew = Color(0xFFE53935);
  static const Color statWatching = Color(0xFF66BB6A);
  static const Color statPlans = Color(0xFFAB7DF6);
  static const Color statCompleted = Color(0xFF64B5F6);
  static const Color statHoldOn = Color(0xFFFFB74D);
  static const Color statDropped = Color(0xFFE57373);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.surface,
      primary: AppColors.light,
      onPrimary: Colors.black,
      secondary: AppColors.textSecondary,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
      fontFamily: 'Roboto',
    ),
    dividerColor: AppColors.outline,
    splashFactory: InkSparkle.splashFactory,
  );
}
