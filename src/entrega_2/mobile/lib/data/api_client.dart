import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'models.dart';

// Cliente HTTP dos endpoints da API (`/v1/auth/*` e `/v1/drills`).
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

/// Uma página da listagem de treinos (`GET /v1/drills`).
class PaginaTreinos {
  const PaginaTreinos({required this.itens, required this.total});

  factory PaginaTreinos.fromJson(Map<String, dynamic> json) => PaginaTreinos(
    itens: [
      for (final item in json['items'] as List)
        _drillFromJson(item as Map<String, dynamic>),
    ],
    total: json['total'] as int,
  );

  final List<Drill> itens;

  /// Total de treinos que batem com o filtro (pode ser maior que [itens]).
  final int total;
}

/// Converte um treino da API para o modelo usado pelas telas. Os parâmetros
/// (lances, intervalo, nível) vêm da versão atual do treino.
Drill _drillFromJson(Map<String, dynamic> json) {
  final versao = json['versao_atual'] as Map<String, dynamic>;
  final intervaloMs = versao['intervalo_ms'] as int;
  return Drill(
    id: '${json['id']}',
    titulo: json['titulo'] as String,
    descricao: json['descricao'] as String? ?? '',
    tipo: json['escopo'] == 'catalogo' ? DrillType.catalogo : DrillType.pessoal,
    lances: versao['qtd_lances'] as int,
    intervaloS: (intervaloMs / 1000).round(),
    intervaloMs: intervaloMs,
    falasTobias: versao['falas_tobias'] as bool?,
    nivel: Nivel.values.firstWhere(
      (n) => n.name == versao['nivel'],
      orElse: () => Nivel.personalizado,
    ),
  );
}

class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  Uri _uri(String caminho) => Uri.parse('${ApiConfig.baseUrl}$caminho');

  /// POST /v1/auth/cadastro → 201 com o usuário criado. [dataNascimento]
  /// vai como AAAA-MM-DD; [perfil] é casual, iniciante ou infantil.
  /// 409 = e-mail ou apelido já usados (ver `detail`).
  Future<UsuarioApi> cadastro({
    required String email,
    required String senha,
    required String nome,
    required String apelido,
    required String dataNascimento,
    String? perfil,
  }) async {
    final json = await _enviar(
      () => _http.post(
        _uri('/v1/auth/cadastro'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'senha': senha,
          'nome': nome,
          'apelido': apelido,
          'data_nascimento': dataNascimento,
          if (perfil != null) 'perfil': perfil,
        }),
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

  /// GET /v1/drills → uma página de treinos. Sem [escopo], lista catálogo e
  /// pessoais juntos. 401 = token expirado.
  Future<PaginaTreinos> listarTreinos(
    String token, {
    String? escopo,
    String? nivel,
    String? busca,
    int? limit,
    int? offset,
  }) async {
    final query = {
      if (escopo != null) 'escopo': escopo,
      if (nivel != null) 'nivel': nivel,
      if (busca != null && busca.isNotEmpty) 'busca': busca,
      if (limit != null) 'limit': '$limit',
      if (offset != null) 'offset': '$offset',
    };
    final json = await _enviar(
      () => _http.get(
        _uri('/v1/drills').replace(queryParameters: query),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    return PaginaTreinos.fromJson(json);
  }

  /// POST /v1/drills → 201 com o treino criado. Escopo e dono não são
  /// enviados: a API deriva do usuário do [token].
  Future<Drill> criarTreino(
    String token, {
    required String titulo,
    String? descricao,
    required Nivel nivel,
    required int qtdLances,
    required int intervaloMs,
    required bool falasTobias,
  }) async {
    final json = await _enviar(
      () => _http.post(
        _uri('/v1/drills'),
        headers: _jsonComToken(token),
        body: _corpoTreino(
          titulo: titulo,
          descricao: descricao,
          nivel: nivel,
          qtdLances: qtdLances,
          intervaloMs: intervaloMs,
          falasTobias: falasTobias,
        ),
      ),
    );
    return _drillFromJson(json);
  }

  /// GET /v1/drills/{id} → detalhe do treino. 404 = não existe.
  Future<Drill> obterTreino(String token, String id) async {
    final json = await _enviar(
      () => _http.get(
        _uri('/v1/drills/$id'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    return _drillFromJson(json);
  }

  /// PUT /v1/drills/{id} → 200 com o treino editado (nova versão).
  /// 404 = o treino não é do usuário (ou não existe).
  Future<Drill> editarTreino(
    String token,
    String id, {
    required String titulo,
    String? descricao,
    required Nivel nivel,
    required int qtdLances,
    required int intervaloMs,
    required bool falasTobias,
  }) async {
    final json = await _enviar(
      () => _http.put(
        _uri('/v1/drills/$id'),
        headers: _jsonComToken(token),
        body: _corpoTreino(
          titulo: titulo,
          descricao: descricao,
          nivel: nivel,
          qtdLances: qtdLances,
          intervaloMs: intervaloMs,
          falasTobias: falasTobias,
        ),
      ),
    );
    return _drillFromJson(json);
  }

  /// POST /v1/drills/{id}/copy → 201 com a cópia nos pessoais do usuário,
  /// com os mesmos valores do original.
  Future<Drill> copiarTreino(String token, String id) async {
    final json = await _enviar(
      () => _http.post(
        _uri('/v1/drills/$id/copy'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    return _drillFromJson(json);
  }

  /// DELETE /v1/drills/{id} → 204 sem corpo. 403 = treino do catálogo;
  /// 404 = o treino não é do usuário (ou não existe).
  Future<void> excluirTreino(String token, String id) async {
    await _enviar(
      () => _http.delete(
        _uri('/v1/drills/$id'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
  }

  Map<String, String> _jsonComToken(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  /// Corpo de criação/edição. Escopo e dono não vão: a API deriva do token.
  String _corpoTreino({
    required String titulo,
    String? descricao,
    required Nivel nivel,
    required int qtdLances,
    required int intervaloMs,
    required bool falasTobias,
  }) => jsonEncode({
    'titulo': titulo,
    if (descricao != null && descricao.isNotEmpty) 'descricao': descricao,
    'nivel': nivel.name,
    'qtd_lances': qtdLances,
    'intervalo_ms': intervaloMs,
    'falas_tobias': falasTobias,
  });

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
