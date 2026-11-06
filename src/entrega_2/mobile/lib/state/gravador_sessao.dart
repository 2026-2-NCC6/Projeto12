import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/fila_sessoes.dart';
import '../transport/device_transport.dart';
import 'sessao_ativa.dart';

/// Grava uma sessão em andamento: conversa com o Tobias e põe cada lance
/// na fila local no instante em que ele chega.
///
/// O que o app decide (e não o firmware):
/// - `bola`: contador do app, de 1 a N, contínuo através das pausas. É mais
///   robusto que o `bola` do JSON, que não é usado;
/// - `ts_ms`: tempo de TREINO no relógio do app, monotônico e parado
///   durante a pausa (ver [pausado]).
/// A contagem e o `millis()` do firmware continuam no `id_lance_firmware`.
///
/// Pausa: a tela segue o estado CONFIRMADO pelo Tobias ([pausado]), nunca o
/// pretendido. Se o comando se perde e a tela dissesse "pausado", o boneco
/// seguiria rodando e acumulando erro por timeout sem o jogador saber.
///
/// UUIDs: o da sessão nasce em [iniciar] e o de cada lance nasce na
/// chegada, e os dois são gravados ANTES de qualquer outra coisa. Gerar na
/// hora de enviar parece equivalente e não é: se o app reiniciar entre o
/// treino e o envio, os mesmos lances ganhariam UUIDs novos e o servidor
/// os gravaria de novo.
class GravadorSessao {
  GravadorSessao({
    required this.sessao,
    required this.fila,
    required this.transport,
    Uuid? uuid,
    DateTime Function()? agora,
    Stopwatch? relogio,
    this.esperaConfirmacao = const Duration(milliseconds: 1500),
  }) : _uuid = uuid ?? const Uuid(),
       _agora = agora ?? DateTime.now,
       _relogio = relogio ?? Stopwatch();

  final SessaoAtiva sessao;
  final FilaSessoes fila;
  final DeviceTransport transport;
  final Uuid _uuid;
  final DateTime Function() _agora;

  /// Quanto [pausar] e [retomar] esperam a confirmação do Tobias.
  final Duration esperaConfirmacao;

  /// Fonte do `ts_ms`. Monotônico (o `DateTime.now()` pode pular se o
  /// relógio do aparelho for acertado no meio da sessão).
  ///
  /// Para na pausa e volta a rodar no retomar: o `ts_ms` mede tempo de
  /// treino, não de relógio. Sem isso, o lance seguinte a uma pausa de dez
  /// minutos chegaria com `ts_ms` de ~650000, um número sem significado.
  /// O firmware faz o contrário de propósito no `t_ms` dele (conta o tempo
  /// pausado), mas aquele campo é ignorado: é este valor que vai para a API.
  final Stopwatch _relogio;

  String? _uuidSessao;
  StreamSubscription<ImpactEvent>? _sub;
  StreamSubscription<StatusTobias>? _subEstados;
  var _bola = 0;
  var _encerrada = false;

  /// Gravações de lances ainda em curso; [encerrar] espera por elas.
  Future<void> _gravacoes = Future.value();

  /// Avisa a tela a cada lance gravado.
  final lancesGravados = ValueNotifier<int>(0);

  /// Se o Tobias CONFIRMOU que está pausado. Segue toda confirmação que
  /// chegar, inclusive atrasada (depois de [esperaConfirmacao]): o firmware
  /// ignora `PAUSAR` quando já está pausado, então uma tela que ficasse em
  /// "rodando" com o boneco pausado não teria como sair dali.
  final pausado = ValueNotifier<bool>(false);

  String get uuidSessao => _uuidSessao!;
  int get lancesRestantes =>
      sessao.lances - _bola < 0 ? 0 : sessao.lances - _bola;

  /// Grava a sessão na fila e SÓ ENTÃO manda o `TREINO:` ao Tobias.
  Future<void> iniciar() async {
    _uuidSessao = _uuid.v4();
    await fila.abrir(
      SessaoLocal(
        uuidSessao: uuidSessao,
        treinoVersaoId: sessao.treinoVersaoId,
        dificuldade: sessao.dificuldade,
        iniciadaEm: isoComFuso(_agora()),
        treinoTitulo: sessao.titulo,
      ),
    );
    _relogio.start();
    // Escuta antes de mandar o comando, para não perder o primeiro lance.
    _sub = transport.events.listen(_aoLance);
    _subEstados = transport.estados.listen(_aoEstado);
    await _enviarTreino(DeviceCommand.iniciarSessao, sessao.lances);
  }

  void _aoLance(ImpactEvent e) {
    if (_encerrada) return;
    if (_bola >= sessao.lances) {
      // O firmware para sozinho no N-ésimo lance; o simulador, não.
      debugPrint('[Sessão] lance além dos ${sessao.lances} ignorado');
      return;
    }
    _bola += 1;
    final lance = LanceLocal(
      uuidLance: _uuid.v4(),
      idLanceFirmware: e.idLance.isEmpty ? null : e.idLance,
      bola: _bola,
      resultado: e.resultado,
      classe: e.classe,
      knockout: e.knockout,
      angulo: e.aPkG,
      tsMs: _relogio.elapsedMilliseconds,
    );
    _gravacoes = _gravacoes.then(
      (_) => fila.registrarLance(uuidSessao, lance).then((_) {
        lancesGravados.value = lancesGravados.value + 1;
      }),
    );
  }

  void _aoEstado(StatusTobias s) {
    if (_encerrada) return;
    switch (s) {
      case StatusTobias.pausado:
        _relogio.stop();
        pausado.value = true;
      case StatusTobias.retomado:
        _relogio.start();
        pausado.value = false;
    }
  }

  /// Manda `PAUSAR` e espera o Tobias confirmar por até [esperaConfirmacao].
  /// `false`: não confirmou a tempo, e a sessão segue rodando.
  Future<bool> pausar() =>
      _comandoConfirmado(DeviceCommand.pausar, querPausado: true);

  /// Manda `RETOMAR` e espera a confirmação, como [pausar]. A sessão no
  /// firmware é a mesma: nada de `TREINO:` novo.
  Future<bool> retomar() =>
      _comandoConfirmado(DeviceCommand.retomar, querPausado: false);

  /// Não trava quem chama além de [esperaConfirmacao]: o envio não é
  /// esperado (uma escrita BLE presa não pode prender a tela), o prazo é.
  Future<bool> _comandoConfirmado(
    DeviceCommand cmd, {
    required bool querPausado,
  }) async {
    if (_encerrada) return false;
    final confirmou = Completer<bool>();
    void conferir() {
      if (pausado.value == querPausado && !confirmou.isCompleted) {
        confirmou.complete(true);
      }
    }

    pausado.addListener(conferir);
    final prazo = Timer(esperaConfirmacao, () {
      if (!confirmou.isCompleted) confirmou.complete(false);
    });
    try {
      unawaited(
        transport.send(cmd).catchError((Object e) {
          debugPrint('[Sessão] falha ao enviar ${cmd.name}: $e');
        }),
      );
      final ok = await confirmou.future;
      if (!ok) {
        debugPrint('[Sessão] Tobias não confirmou ${cmd.name} em '
            '${esperaConfirmacao.inMilliseconds} ms');
      }
      return ok;
    } finally {
      prazo.cancel();
      pausado.removeListener(conferir);
    }
  }

  /// Para o Tobias, espera os lances em gravação e fecha a sessão na fila.
  ///
  /// O STOP sai primeiro e a escuta é cancelada SEM esperar: parar o
  /// hardware não pode depender de desmontar o stream (cujo cancelamento
  /// pode demorar), e `_encerrada` já descarta qualquer lance atrasado.
  Future<void> encerrar() async {
    if (_encerrada) return;
    _encerrada = true;
    await transport.send(DeviceCommand.finalizar);
    unawaited(_sub?.cancel());
    unawaited(_subEstados?.cancel());
    await _gravacoes;
    if (_uuidSessao != null) await fila.encerrar(uuidSessao, _agora());
  }

  Future<void> _enviarTreino(DeviceCommand cmd, int lances) => transport.send(
    cmd,
    lances: lances,
    intervaloMs: sessao.intervaloMs,
    calibracao: sessao.dificuldade,
  );
}
