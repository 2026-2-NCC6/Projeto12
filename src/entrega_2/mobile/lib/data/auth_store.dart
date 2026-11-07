import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Guarda o token de acesso (JWT), o papel, a calibração e os dados do
/// usuário no armazenamento local do aparelho via shared_preferences: salvar
/// após o login, ler para chamar a API e configurar o Tobias, e limpar no
/// logout.
abstract final class AuthStore {
  static const _chaveToken = 'auth_token';
  static const _chavePapel = 'auth_papel';
  static const _chaveCalibracao = 'auth_calibracao';
  static const _chaveUsuario = 'auth_usuario';

  /// O `/v1/auth/eu` mais recente. É daqui que o Perfil tira a identidade
  /// sem rede, e o pareamento decide se ainda falta calibrar.
  static Future<void> salvarUsuario(UsuarioApi usuario) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveUsuario, jsonEncode(usuario.toJson()));
  }

  /// Id de quem está logado: o dono das sessões da fila. Nulo sem login.
  static Future<int?> lerIdUsuario() async {
    if (await lerToken() == null) return null;
    return (await lerUsuario())?.id;
  }

  /// O usuário guardado, ou `null` (sem login, ou login de antes deste campo
  /// existir: aí quem chama busca no `/eu`).
  static Future<UsuarioApi?> lerUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final bruto = prefs.getString(_chaveUsuario);
    if (bruto == null) return null;
    try {
      return UsuarioApi.fromJson(jsonDecode(bruto) as Map<String, dynamic>);
    } on Object {
      return null; // gravado por uma versão antiga e incompatível
    }
  }

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

  /// Salva o nível de calibração / acréscimo de dificuldade em graus.
  static Future<void> salvarCalibracao(double calib) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_chaveCalibracao, calib);
  }

  /// Devolve a calibração salva, ou 0.0 (padrão fácil).
  static Future<double> lerCalibracao() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_chaveCalibracao) ?? 0.0;
  }

  /// Encerra a sessão: apaga token, papel, calibração e usuário locais.
  static Future<void> limparToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveToken);
    await prefs.remove(_chavePapel);
    await prefs.remove(_chaveCalibracao);
    await prefs.remove(_chaveUsuario);
  }
}
