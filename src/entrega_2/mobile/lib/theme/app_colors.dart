import 'package:flutter/painting.dart';

/// Cores semânticas do TOBIAS (TOBIAS_UI_SPEC.md, seção 2).
/// Use sempre estes nomes — nunca cores soltas nas telas.
abstract final class AppColors {
  // bg/*
  static const bgApp = Color(0xFFF2F2F2);
  static const bgSurface = Color(0xFFFFFFFF);
  static const bgSurfaceMuted = Color(0xFFE5E5E5);
  static const bgBrand = Color(0xFF1D591B);
  static const bgBrandStrong = Color(0xFF133C12);
  static const bgInverse = Color(0xFF091E09);
  static const bgBrandSoft = Color(0xFFE9F9E8);
  static const bgAccent = Color(0xFF63F25E);
  static const bgAccentSoft = Color(0xFFD8FCD7);
  static const bgTertiarySoft = Color(0xFFE9F0F9);
  static const bgError = Color(0xFFBA1A1A);
  static const bgErrorSoft = Color(0xFFFFDAD6);
  static const bgWarning = Color(0xFFE8A317);
  static const bgWarningSoft = Color(0xFFFFF1CC);

  // text/*
  static const textPrimary = Color(0xFF191919);
  static const textSecondary = Color(0xFF485B77);
  static const textBrand = Color(0xFF1D591B);
  static const textOnBrand = Color(0xFFFFFFFF);
  static const textOnBrandMuted = Color(0xFFD3F4D2);
  static const textOnAccent = Color(0xFF091E09);
  static const textError = Color(0xFFBA1A1A);
  static const textWarning = Color(0xFF8A5A00);

  // border/*
  static const borderDefault = Color(0xFFE5E5E5);
  static const borderStrong = Color(0xFF91A9CB);
  static const borderBrand = Color(0xFF1D591B);
  static const borderAccent = Color(0xFF63F25E);
  static const borderError = Color(0xFFBA1A1A);

  // icon/*
  static const iconDefault = Color(0xFF64748B);
  static const iconPrimary = Color(0xFF191919);
  static const iconBrand = Color(0xFF1D591B);
  static const iconOnBrand = Color(0xFFFFFFFF);
  static const iconOnAccent = Color(0xFF091E09);
  static const iconAccent = Color(0xFF63F25E);
  static const iconError = Color(0xFFBA1A1A);

  /// Overlay de diálogo: preto a 55%.
  static const overlay = Color(0x8C000000);
}
