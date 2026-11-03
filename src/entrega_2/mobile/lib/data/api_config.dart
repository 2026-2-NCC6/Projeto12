import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configuração de acesso à API (FastAPI).
///
/// - Web: localhost
/// - Celular Android: IP local da máquina na rede Wi-Fi (ex: 192.168.15.2:8000)
abstract final class ApiConfig {
  static const _webUrl = 'http://localhost:8000';
  static const _defaultAndroidUrl = 'http://192.168.15.2:8000';

  static String _overrideUrl = '';

  static String get baseUrl {
    if (_overrideUrl.isNotEmpty) return _overrideUrl;
    return kIsWeb ? _webUrl : _defaultAndroidUrl;
  }

  static set baseUrl(String url) {
    _overrideUrl = url;
  }

  static Future<void> carregarConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salvo = prefs.getString('api_base_url');
      if (salvo != null && salvo.isNotEmpty) {
        _overrideUrl = salvo;
      }
    } catch (_) {}
  }

  static Future<void> salvarUrl(String url) async {
    _overrideUrl = url.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('api_base_url', _overrideUrl);
    } catch (_) {}
  }

  /// Tempo máximo de espera por uma resposta da API.
  static const timeout = Duration(seconds: 10);
}
