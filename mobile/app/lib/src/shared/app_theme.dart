import 'package:flutter/material.dart';

class AppColors {
  static const deepBlack = Color(0xFF0A0A0A);
  static const graphite = Color(0xFF121212);
  static const charcoal = Color(0xFF1A1A1A);
  static const elevatedSurface = Color(0xFF1E1E1E);
  static const cardSurface = Color(0xFF202020);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color.fromRGBO(255, 255, 255, 0.6);
  static const textTertiary = Color.fromRGBO(255, 255, 255, 0.35);
  static const borderSubtle = Color.fromRGBO(255, 255, 255, 0.06);
  static const borderHighlight = Color.fromRGBO(255, 255, 255, 0.12);
  static const glow = Color.fromRGBO(230, 236, 255, 0.14);
}

class AppSpacing {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = base.textTheme.apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.deepBlack,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.graphite,
      primary: AppColors.textPrimary,
      onPrimary: AppColors.deepBlack,
      onSurface: AppColors.textPrimary,
    ),
    textTheme: textTheme.copyWith(
      headlineLarge: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
      headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      bodySmall: textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.elevatedSurface,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.graphite.withValues(alpha: 0.92),
      indicatorColor: Colors.white.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          size: 22,
        );
      }),
    ),
  );
}
