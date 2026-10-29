import 'package:flutter/foundation.dart';

/// Configuração de acesso à API (FastAPI). A URL base fica só aqui.
///
/// - Web: o navegador roda na mesma máquina da API → `localhost`.
/// - Emulador Android: `10.0.2.2` é o apelido do emulador para o
///   `localhost` do computador hospedeiro.
abstract final class ApiConfig {
  static const _webUrl = 'http://localhost:8000';
  static const _androidEmuladorUrl = 'http://10.0.2.2:8000';

  static String get baseUrl => kIsWeb ? _webUrl : _androidEmuladorUrl;

  /// Tempo máximo de espera por uma resposta da API.
  static const timeout = Duration(seconds: 15);
}
