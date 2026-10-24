import 'package:flutter/foundation.dart';

/// Preferências globais simples do app (somente em memória).
abstract final class AppSettings {
  /// Acessibilidade → Tamanho do texto: "Padrão" (false) ou "Grande" (true).
  static final textoGrande = ValueNotifier<bool>(false);

  /// Fator aplicado à escala de texto quando "Grande" está ativo.
  static const escalaGrande = 1.15;
}
