import 'package:shared_preferences/shared_preferences.dart';

/// Configuração de acesso à API (FastAPI).
///
/// A URL padrão é a API hospedada no Azure. Para apontar para outro servidor
/// (ex.: desenvolvimento local), passe-a na compilação:
///
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000
///
/// Também é possível sobrescrevê-la em tempo de execução pela tela de login
/// (fica salva em SharedPreferences).
abstract final class ApiConfig {
  static const _defaultUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        'https://tobias-api.icywater-8a34b57b.mexicocentral.azurecontainerapps.io',
  );

  static String _overrideUrl = '';

  static String get baseUrl =>
      _overrideUrl.isNotEmpty ? _overrideUrl : _defaultUrl;

  static set baseUrl(String url) {
    _overrideUrl = url;
  }

  static Future<void> carregarConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salvo = prefs.getString('api_base_url')?.trim();
      if (salvo == null || salvo.isEmpty) return;
      // URLs http:// salvas (ex.: IP local antigo) não funcionam mais, pois o
      // Android bloqueia tráfego sem TLS: descarta e volta para a padrão.
      if (salvo.toLowerCase().startsWith('http://')) {
        await prefs.remove('api_base_url');
        return;
      }
      _overrideUrl = salvo;
    } catch (_) {}
  }

  static Future<void> salvarUrl(String url) async {
    _overrideUrl = url.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_base_url', _overrideUrl);
    } catch (_) {}
  }

  /// Tempo máximo de espera por uma resposta da API. A API dorme quando fica
  /// ociosa e a primeira requisição pode levar até ~30 s para acordá-la.
  static const timeout = Duration(seconds: 45);
}
