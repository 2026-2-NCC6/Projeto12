import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

// Cliente HTTP dos endpoints de autenticação da API (`/v1/auth/*`).
//
// Qualquer resposta fora da faixa 2xx vira uma ApiException com a
// mensagem do campo `detail` devolvido pela API, pronta para mostrar na tela.

/// Erro devolvido pela API (ou falha de conexão, com [statusCode] nulo).
class ApiException implements Exception {
  const ApiException(this.mensagem, {this.statusCode});

  final String mensagem;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $mensagem';
}

/// Usuário autenticado, como devolvido por cadastro e `/eu`.
class UsuarioApi {
  const UsuarioApi({required this.id, required this.email, required this.papel});

  factory UsuarioApi.fromJson(Map<String, dynamic> json) => UsuarioApi(
    id: json['id'] as int,
    email: json['email'] as String,
    papel: json['papel'] as String,
  );

  final int id;
  final String email;
  final String papel;
}

class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Uri _uri(String caminho) => Uri.parse('${ApiConfig.baseUrl}$caminho');

  /// POST /v1/auth/cadastro → 201 com o usuário criado.
  Future<UsuarioApi> cadastro(String email, String senha) async {
    final json = await _enviar(
      () => _http.post(
        _uri('/v1/auth/cadastro'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'senha': senha}),
      ),
    );
    return UsuarioApi.fromJson(json);
  }

  /// POST /v1/auth/login → devolve o `access_token` (JWT, expira em 30 min).
  Future<String> login(String email, String senha) async {
    final json = await _enviar(
      () => _http.post(
        _uri('/v1/auth/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'senha': senha}),
      ),
    );
    return json['access_token'] as String;
  }

  /// GET /v1/auth/eu → dados do usuário dono do [token].
  Future<UsuarioApi> eu(String token) async {
    final json = await _enviar(
      () => _http.get(
        _uri('/v1/auth/eu'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    return UsuarioApi.fromJson(json);
  }

  /// Executa a requisição, trata falhas de rede e converte não-2xx em
  /// [ApiException] com a mensagem de `detail`.
  Future<Map<String, dynamic>> _enviar(
    Future<http.Response> Function() requisicao,
  ) async {
    final http.Response resp;
    try {
      resp = await requisicao().timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw const ApiException('O servidor demorou para responder.');
    } catch (_) {
      throw const ApiException('Não foi possível conectar ao servidor.');
    }

    final corpo = _decodificar(resp);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return corpo is Map<String, dynamic> ? corpo : const {};
    }
    throw ApiException(_mensagemDeErro(corpo, resp.statusCode),
        statusCode: resp.statusCode);
  }

  dynamic _decodificar(http.Response resp) {
    if (resp.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// Usa o `detail` da API. O 422 (validação do FastAPI) vem em inglês e
  /// técnico, então nunca é mostrado cru: vira uma mensagem genérica.
  String _mensagemDeErro(dynamic corpo, int status) {
    if (status == 422) return 'Verifique os dados preenchidos.';
    final detail = corpo is Map ? corpo['detail'] : null;
    if (detail is String && detail.isNotEmpty) return detail;
    return 'Erro inesperado (HTTP $status).';
  }
}
