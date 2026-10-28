import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Tipografia do TOBIAS (Roboto). `height` = altura de linha / tamanho.
abstract final class AppText {
  static const _family = 'Roboto';

  static TextStyle _s(
    double size,
    double line,
    FontWeight weight, [
    double spacing = 0,
  ]) => TextStyle(
    fontFamily: _family,
    fontSize: size,
    height: line / size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: AppColors.textPrimary,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static final displayScore = _s(56, 60, FontWeight.w700, -1);
  static final displayLarge = _s(40, 48, FontWeight.w700, -0.5);
  static final headlineL = _s(28, 34, FontWeight.w700);
  static final headlineM = _s(24, 30, FontWeight.w700);
  static final titleL = _s(20, 26, FontWeight.w700);
  static final titleM = _s(16, 22, FontWeight.w600);
  static final bodyL = _s(16, 24, FontWeight.w400);
  static final bodyM = _s(14, 20, FontWeight.w400);
  static final bodyS = _s(12, 16, FontWeight.w400);
  static final labelL = _s(14, 20, FontWeight.w500, 0.1);
  static final labelM = _s(12, 16, FontWeight.w500, 0.2);
  static final labelS = _s(11, 14, FontWeight.w500, 0.5);
  static final button = _s(16, 20, FontWeight.w600, 0.2);
}

extension TextStyleColor on TextStyle {
  /// Atalho para trocar a cor: `AppText.bodyS.c(AppColors.textSecondary)`.
  TextStyle c(Color color) => copyWith(color: color);
}
