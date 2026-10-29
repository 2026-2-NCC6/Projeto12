import 'package:shared_preferences/shared_preferences.dart';

/// Guarda o token de acesso (JWT) no armazenamento local do aparelho
/// via shared_preferences: salvar após o login, ler para chamar a API
/// e limpar no logout ou quando o token expirar (401).
abstract final class AuthStore {
  static const _chaveToken = 'auth_token';

  static Future<void> salvarToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveToken, token);
  }

  /// Devolve o token salvo, ou `null` se não houver sessão.
  static Future<String?> lerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_chaveToken);
  }

  static Future<void> limparToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveToken);
  }
}
