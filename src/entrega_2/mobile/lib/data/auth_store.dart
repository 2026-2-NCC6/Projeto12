import 'package:shared_preferences/shared_preferences.dart';

/// Guarda o token de acesso (JWT) e o papel do usuário no armazenamento
/// local do aparelho via shared_preferences: salvar após o login, ler para
/// chamar a API e limpar no logout ou quando o token expirar (401).
abstract final class AuthStore {
  static const _chaveToken = 'auth_token';
  static const _chavePapel = 'auth_papel';

  static Future<void> salvarToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveToken, token);
  }

  /// Devolve o token salvo, ou `null` se não houver sessão.
  static Future<String?> lerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_chaveToken);
  }

  /// Papel devolvido por `/v1/auth/eu` ("jogador" ou "admin").
  static Future<void> salvarPapel(String papel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chavePapel, papel);
  }

  /// Sem papel salvo, o usuário é tratado como jogador.
  static Future<bool> ehAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_chavePapel) == 'admin';
  }

  /// Encerra a sessão: apaga o token e o papel.
  static Future<void> limparToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveToken);
    await prefs.remove(_chavePapel);
  }
}
