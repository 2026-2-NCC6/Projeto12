import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    scaffoldBackgroundColor: AppColors.bgApp,
    colorScheme: const ColorScheme.light(
      primary: AppColors.bgBrand,
      onPrimary: AppColors.textOnBrand,
      secondary: AppColors.bgAccent,
      onSecondary: AppColors.textOnAccent,
      tertiary: AppColors.iconDefault,
      error: AppColors.bgError,
      onError: AppColors.textOnBrand,
      surface: AppColors.bgSurface,
      onSurface: AppColors.textPrimary,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.borderBrand,
      selectionColor: AppColors.bgAccentSoft,
      selectionHandleColor: AppColors.bgBrand,
    ),
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(),
  );
}
