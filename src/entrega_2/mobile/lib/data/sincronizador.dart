import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_store.dart';
import 'fila_sessoes.dart';

/// Como terminou uma rodada de envio.
enum ResultadoSincronizacao {
  /// Tudo o que aguardava foi enviado (ou não havia nada).
  concluida,

  /// Sem token, ou token expirado: só volta depois de um novo login.
  precisaLogin,

  /// Rede fora, timeout ou 5xx: nova tentativa já agendada.
  tentaraDeNovo,

  /// Outro erro da API (4xx inesperado): para até o próximo gatilho.
  interrompida,
}

/// Envia a fila local para `POST /v1/sessions` (US-606 / RF21).
///
/// Gatilhos: fim da sessão, abertura do app (e login) e o temporizador de
/// nova tentativa. Sem pacote de detecção de rede: se a rede voltou, a
/// tentativa seguinte simplesmente funciona.
///
/// Uma rodada por vez: chamadas durante um envio recebem a mesma rodada, então
/// a mesma sessão nunca vai em dois envios simultâneos.
class Sincronizador {
  Sincronizador({
    FilaSessoes Function()? fila,
    ApiClient? api,
    Future<String?> Function()? lerToken,
    Future<String?> Function()? renovarToken,
    math.Random? aleatorio,
    this.esperaInicial = const Duration(seconds: 2),
    this.esperaMaxima = const Duration(minutes: 5),
    this.tamanhoLote = 50,
  }) : _fila = fila ?? (() => FilaSessoes.doApp),
       _api = api ?? ApiClient(),
       _lerToken = lerToken ?? AuthStore.lerToken,
       _renovarToken = renovarToken ?? _semRenovacao,
       _aleatorio = aleatorio ?? math.Random();

  static final doApp = Sincronizador();

  final FilaSessoes Function() _fila;
  final ApiClient _api;
  final Future<String?> Function() _lerToken;
  final Future<String?> Function() _renovarToken;
  final math.Random _aleatorio;
  final Duration esperaInicial;
  final Duration esperaMaxima;
  final int tamanhoLote;

  /// Mensagens para o usuário (ex.: sessão rejeitada), exibidas pelo app.
  final _avisos = StreamController<String>.broadcast();
  Stream<String> get avisos => _avisos.stream;

  Future<ResultadoSincronizacao>? _emCurso;
  Timer? _novaTentativa;
  var _falhasSeguidas = 0;

  /// Espera da próxima tentativa agendada (para testes e diagnóstico).
  @visibleForTesting
  Duration? ultimaEspera;

  /// Renovação automática do login: DELIBERADAMENTE NÃO IMPLEMENTADA.
  ///
  /// Num 401 o app pede um novo login, e o envio é retomado depois dele
  /// (gatilho do login). Isso é o comportamento correto, não uma lacuna:
  /// - guardar a senha no aparelho para relogar sozinho está fora de
  ///   questão;
  /// - um endpoint de renovação com rotação de token é uma US inteira,
  ///   fora do prazo.
  /// O incômodo é resolvido por configuração: o token dura 7 dias
  /// (`JWT_EXPIRE_MINUTES` no servidor), então o 401 no envio é raro.
  ///
  /// O parâmetro `renovarToken` continua existindo (e testado) para quando
  /// houver um endpoint de renovação.
  static Future<String?> _semRenovacao() async => null;

  /// Dispara uma rodada de envio sem bloquear quem chamou.
  void disparar() => unawaited(sincronizar());

  /// Uma rodada de envio. Se já houver uma em curso, devolve a mesma.
  Future<ResultadoSincronizacao> sincronizar() {
    return _emCurso ??= _rodada().whenComplete(() => _emCurso = null);
  }

  Future<ResultadoSincronizacao> _rodada() async {
    _novaTentativa?.cancel();
    final fila = _fila();

    // Corpos montados de uma vez. O que chegar durante o envio fica para a
    // próxima rodada (a fila só marca como enviada a versão que foi).
    final preparados = await fila.prepararEnvio();
    if (preparados.isEmpty) return ResultadoSincronizacao.concluida;

    var token = await _lerToken();
    if (token == null) return _precisaLogin();

    // A API dorme quando ociosa; a primeira requisição pode levar ~30 s.
    await _api.acordarApi();

    for (var i = 0; i < preparados.length; i += tamanhoLote) {
      final lote = preparados.sublist(
        i,
        math.min(i + tamanhoLote, preparados.length),
      );
      final resultado = await _enviarLote(fila, lote, token!, (novo) {
        token = novo;
      });
      if (resultado != null) return resultado;
    }

    _falhasSeguidas = 0;
    return ResultadoSincronizacao.concluida;
  }

  /// Envia um lote. Devolve null se a rodada pode seguir.
  Future<ResultadoSincronizacao?> _enviarLote(
    FilaSessoes fila,
    List<EnvioPreparado> lote,
    String token,
    void Function(String) trocarToken, {
    bool jaRenovou = false,
  }) async {
    try {
      final respostas = await _api.enviarSessoes(token, [
        for (final e in lote) e.corpo,
      ]);
      final rejeitadas = await fila.aplicarRespostas(lote, [
        for (final r in respostas) RespostaSessao.fromJson(r),
      ]);
      for (final r in rejeitadas) {
        debugPrint(
          '[Envio] sessão ${r.uuidSessao} rejeitada pela API '
          '(motivo: ${r.motivo}) e removida',
        );
        _avisos.add(avisoDeRejeitada(r.motivo));
      }
      return null;
    } on ApiException catch (e) {
      final status = e.statusCode;

      if (status == 401) {
        if (jaRenovou) return _precisaLogin();
        final novo = await _renovarToken();
        if (novo == null) return _precisaLogin();
        trocarToken(novo);
        return _enviarLote(fila, lote, novo, trocarToken, jaRenovou: true);
      }

      if (status == 422) {
        // Lote malformado: descobre qual sessão é, enviando uma a uma. As
        // que falharem sozinhas ficam separadas, sem nova tentativa.
        if (lote.length == 1) {
          _logPayloadInvalido(lote.single.uuidSessao, e.corpo);
          await fila.separar(lote.single.uuidSessao, 'payload_invalido');
          return null;
        }
        debugPrint(
          '[Envio] 422 num lote de ${lote.length}: reenviando uma a uma '
          'para achar a sessão inválida. Resposta: ${e.corpo}',
        );
        for (final e in lote) {
          final r = await _enviarLote(fila, [e], token, trocarToken);
          if (r != null) return r;
        }
        return null;
      }

      if (status == null || status >= 500) return _agendarNovaTentativa(e);

      debugPrint('[Envio] erro inesperado da API ($status): ${e.mensagem}');
      return ResultadoSincronizacao.interrompida;
    }
  }

  /// Frase para o usuário conforme o `motivo` da rejeição.
  @visibleForTesting
  static String avisoDeRejeitada(String? motivo) => switch (motivo) {
    'versao_invalida' =>
      'Uma sessão não pôde ser registrada: o treino dela não existe mais '
          'no servidor. A sessão foi descartada.',
    _ =>
      'Uma sessão foi recusada pelo servidor e descartada.',
  };

  /// Um 422 quer dizer que o APP montou um payload que a API não aceita:
  /// é bug nosso, não condição esperada. Registro em destaque, com o que é
  /// preciso para reproduzir.
  void _logPayloadInvalido(String uuidSessao, String? resposta) {
    debugPrint(
      '\n'
      '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
      '!!! [Envio] BUG DO APP: 422 (payload inválido) em POST /v1/sessions\n'
      '!!! uuid_sessao: $uuidSessao\n'
      '!!! resposta do servidor: ${resposta ?? '(vazia)'}\n'
      '!!! A sessão foi separada e não será reenviada.\n'
      '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!',
    );
  }

  ResultadoSincronizacao _precisaLogin() {
    // A rodada terminou: a próxima falha temporária (depois do novo login)
    // recomeça a espera do início, não de onde parou antes.
    _falhasSeguidas = 0;
    debugPrint('[Envio] sem login válido: envio retomado no próximo login');
    _avisos.add('Entre de novo para enviar suas sessões salvas no celular.');
    return ResultadoSincronizacao.precisaLogin;
  }

  /// Espera exponencial com variação aleatória: ~2 s, 4 s, 8 s… até ~5 min.
  /// A variação (metade fixa, metade sorteada) evita que muitos aparelhos
  /// voltem todos no mesmo instante.
  ResultadoSincronizacao _agendarNovaTentativa(ApiException e) {
    final base = esperaInicial * math.pow(2, _falhasSeguidas).toInt();
    final limite = base > esperaMaxima ? esperaMaxima : base;
    _falhasSeguidas = math.min(_falhasSeguidas + 1, 20);
    final espera = limite * 0.5 + limite * (0.5 * _aleatorio.nextDouble());
    ultimaEspera = espera;
    debugPrint(
      '[Envio] falha temporária (${e.statusCode ?? 'rede'}): nova tentativa '
      'em ${espera.inMilliseconds} ms',
    );
    _novaTentativa?.cancel();
    _novaTentativa = Timer(espera, disparar);
    return ResultadoSincronizacao.tentaraDeNovo;
  }

  /// Cancela a nova tentativa agendada (testes).
  @visibleForTesting
  void cancelarAgendamento() => _novaTentativa?.cancel();
}
