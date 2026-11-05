import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/fila_sessoes.dart';
import '../transport/device_transport.dart';
import 'sessao_ativa.dart';

/// Grava uma sessão em andamento: conversa com o Tobias e põe cada lance
/// na fila local no instante em que ele chega.
///
/// O que o app decide (e não o firmware), porque o firmware reinicia tudo
/// a cada `TREINO:` — inclusive no retomar depois de uma pausa:
/// - `bola`: contador do app, de 1 a N, contínuo através das pausas;
/// - `ts_ms`: tempo desde o início da sessão no relógio do app, monotônico;
/// - quantos lances faltam, mandados no `TREINO:` do retomar.
/// A contagem e o `millis()` do firmware continuam no `id_lance_firmware`.
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
  }) : _uuid = uuid ?? const Uuid(),
       _agora = agora ?? DateTime.now,
       _relogio = relogio ?? Stopwatch();

  final SessaoAtiva sessao;
  final FilaSessoes fila;
  final DeviceTransport transport;
  final Uuid _uuid;
  final DateTime Function() _agora;

  /// Monotônico (o `DateTime.now()` pode pular se o relógio do aparelho
  /// for acertado no meio da sessão).
  final Stopwatch _relogio;

  String? _uuidSessao;
  StreamSubscription<ImpactEvent>? _sub;
  var _bola = 0;
  var _encerrada = false;

  /// Gravações de lances ainda em curso; [encerrar] espera por elas.
  Future<void> _gravacoes = Future.value();

  /// Avisa a tela a cada lance gravado.
  final lancesGravados = ValueNotifier<int>(0);

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
      ),
    );
    _relogio.start();
    // Escuta antes de mandar o comando, para não perder o primeiro lance.
    _sub = transport.events.listen(_aoLance);
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

  Future<void> pausar() => transport.send(DeviceCommand.pausar);

  /// Retoma pedindo só os lances que faltam: o firmware recomeça a contagem
  /// do zero a cada `TREINO:`. Sem nada faltando, não manda nada.
  Future<void> retomar() async {
    if (lancesRestantes == 0) return;
    await _enviarTreino(DeviceCommand.retomar, lancesRestantes);
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
