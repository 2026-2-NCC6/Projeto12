import 'package:flutter/painting.dart';

/// Raios usados no design.
abstract final class AppRadius {
  static const r7 = 7.0;
  static const r8 = 8.0;
  static const r12 = 12.0;
  static const r16 = 16.0;
  static const r20 = 20.0;
  static const r24 = 24.0;
  static const r28 = 28.0;
  static const pill = 999.0;
}

/// Margem lateral padrão das telas.
const kScreenPadding = 24.0;

/// Sombras do design.
abstract final class AppShadows {
  /// offset (0,2) blur 8, #1A331A a 8%.
  static const card = [
    BoxShadow(offset: Offset(0, 2), blurRadius: 8, color: Color(0x141A331A)),
  ];

  /// offset (0,8) blur 24, #1C591A a 22%.
  static const raised = [
    BoxShadow(offset: Offset(0, 8), blurRadius: 24, color: Color(0x381C591A)),
  ];

  /// offset (0,0) blur 24, #63F25E a 45%.
  static const glowAccent = [
    BoxShadow(blurRadius: 24, color: Color(0x7363F25E)),
  ];
}
