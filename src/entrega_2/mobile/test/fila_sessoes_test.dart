import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/state/gravador_sessao.dart';
import 'package:smart_tennis_arena_mobile/state/sessao_ativa.dart';
import 'package:smart_tennis_arena_mobile/transport/device_transport.dart';

/// Faz o papel do Tobias: o teste emite os lances e lê os comandos.
class _TobiasFalso implements DeviceTransport {
  final _eventos = StreamController<ImpactEvent>.broadcast();
  final _estados = StreamController<StatusTobias>.broadcast();
  final comandos = <String>[];

  /// Chamado a cada comando, antes de registrá-lo.
  Future<void> Function(String comando)? aoReceber;

  /// `false` simula o comando (ou a resposta) perdido no BLE.
  var responde = true;

  /// Simula o firmware: a contagem de bola recomeça a cada TREINO e é
  /// preservada no PAUSAR/RETOMAR.
  var _bolaFirmware = 0;
  var _millis = 1000;

  void lance({String resultado = 'acerto', double angulo = 45.0}) {
    _bolaFirmware++;
    _millis += 3137;
    final erro = resultado == 'erro';
    _eventos.add(
      ImpactEvent(
        aPkG: erro ? 0.0 : angulo,
        tMs: _millis,
        resultado: resultado,
        classe: erro ? 'sem_impacto' : 'medio',
        bola: _bolaFirmware,
        idLance: 'L-$_millis-$_bolaFirmware',
      ),
    );
  }

  /// Confirmação vinda do aparelho, a qualquer momento (inclusive atrasada).
  void confirmar(StatusTobias s) => _estados.add(s);

  @override
  Stream<ImpactEvent> get events => _eventos.stream;

  @override
  Stream<StatusTobias> get estados => _estados.stream;

  @override
  Future<void> send(
    DeviceCommand cmd, {
    int lances = 15,
    int intervaloMs = 3000,
    double calibracao = 0.0,
  }) async {
    final c = montarComando(
      cmd,
      lances: lances,
      intervaloMs: intervaloMs,
      calibracao: calibracao,
    ).trim();
    await aoReceber?.call(c);
    if (c.startsWith('TREINO')) _bolaFirmware = 0;
    comandos.add(c);
    if (responde && c == 'PAUSAR') confirmar(StatusTobias.pausado);
    if (responde && c == 'RETOMAR') confirmar(StatusTobias.retomado);
  }

  @override
  Future<DeviceStatus> status() async =>
      const DeviceStatus(nome: 'TOBIAS', conectado: true, bateria: 90);

  @override
  Future<void> disconnect() async {}
}

/// Relógio controlado pelo teste: `ms` é o relógio de parede, que o teste
/// avança; o cronômetro só acumula enquanto está rodando, como o Stopwatch.
class _RelogioFalso implements Stopwatch {
  var ms = 0;
  var _acumulado = 0;
  int? _desde;

  @override
  void start() => _desde ??= ms;

  @override
  void stop() {
    if (_desde == null) return;
    _acumulado += ms - _desde!;
    _desde = null;
  }

  @override
  int get elapsedMilliseconds =>
      _acumulado + (_desde == null ? 0 : ms - _desde!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SessaoAtiva _sessao({int lances = 15, double dificuldade = 0}) =>
    SessaoAtiva.iniciar(
      PaginaTreinos.fromJson({
        'items': [
          {
            'id': 7,
            'titulo': 'Treino de teste',
            'descricao': '',
            'escopo': 'pessoal',
            'versao_atual': {
              'id': 321,
              'numero': 1,
              'nivel': 'medio',
              'qtd_lances': lances,
              'intervalo_ms': 3000,
              'falas_tobias': true,
            },
          },
        ],
        'total': 1,
      }).itens.single,
      dificuldade: dificuldade,
    );

/// Espera as gravações assíncronas dos lances terminarem.
Future<void> _ate(GravadorSessao g, int lances) async {
  for (var i = 0; i < 1000 && g.lancesGravados.value < lances; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(g.lancesGravados.value, lances, reason: 'lances não gravados a tempo');
}

/// Simula matar o app: descarta tudo o que estava em memória e sobe um
/// "processo novo" só com o que foi de fato gravado no shared_preferences.
Future<FilaSessoes> _matarEReabrir() async {
  final gravado = (await SharedPreferences.getInstance()).getString(
    FilaSessoes.chave,
  );
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues({
    if (gravado != null) FilaSessoes.chave: gravado,
  });
  return FilaSessoes();
}

void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  test('matar o app no 8º lance e reabrir: nada se perde nem muda', () async {
    final tobias = _TobiasFalso();
    final gravador = GravadorSessao(
      sessao: _sessao(lances: 15),
      fila: FilaSessoes(),
      transport: tobias,
    );
    await gravador.iniciar();
    for (var i = 0; i < 8; i++) {
      tobias.lance(resultado: i == 4 ? 'erro' : 'acerto');
    }
    await _ate(gravador, 8);

    // O que o app tinha em memória quando "morreu".
    final antes = (await gravador.fila.todas()).single;

    final depois = (await (await _matarEReabrir()).todas()).single;

    expect(depois.uuidSessao, antes.uuidSessao);
    expect(depois.uuidSessao, gravador.uuidSessao);
    expect(depois.treinoVersaoId, 321);
    expect(depois.encerradaEm, isNull);
    expect(depois.sincronizada, isFalse);
    expect(depois.lances, hasLength(8));
    expect(
      [for (final l in depois.lances) l.uuidLance],
      [for (final l in antes.lances) l.uuidLance],
    );
    expect([for (final l in depois.lances) l.bola], [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(depois.lances.map((l) => l.uuidLance).toSet(), hasLength(8));
    expect(depois.lances[4].resultado, 'erro');
  });

  group('pausa', () {
    late _TobiasFalso tobias;
    late _RelogioFalso relogio;
    late GravadorSessao gravador;

    setUp(() async {
      tobias = _TobiasFalso();
      relogio = _RelogioFalso();
      gravador = GravadorSessao(
        sessao: _sessao(lances: 10, dificuldade: 2.5),
        fila: FilaSessoes(),
        transport: tobias,
        relogio: relogio,
        esperaConfirmacao: const Duration(milliseconds: 50),
      );
      await gravador.iniciar();
    });

    Future<void> lances(int n) async {
      for (var i = 0; i < n; i++) {
        relogio.ms += 3100;
        tobias.lance();
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('PAUSAR confirmado pausa, sem STOP nem TREINO: novo', () async {
      await lances(4);
      expect(await gravador.pausar(), isTrue);
      expect(gravador.pausado.value, isTrue);
      expect(tobias.comandos, ['TREINO:10:3000:2.5', 'PAUSAR']);

      expect(await gravador.retomar(), isTrue);
      expect(gravador.pausado.value, isFalse);
      expect(tobias.comandos, ['TREINO:10:3000:2.5', 'PAUSAR', 'RETOMAR']);

      await lances(6);
      await _ate(gravador, 10);
      await gravador.encerrar();
      // O único STOP é o do fim da sessão.
      expect(tobias.comandos, [
        'TREINO:10:3000:2.5',
        'PAUSAR',
        'RETOMAR',
        'STOP',
      ]);
    });

    test('sem confirmação no prazo, não pausa', () async {
      tobias.responde = false;
      expect(await gravador.pausar(), isFalse);
      expect(gravador.pausado.value, isFalse);
      // O relógio seguiu rodando: o boneco não parou.
      relogio.ms += 5000;
      expect(relogio.elapsedMilliseconds, 5000);
    });

    test('sem confirmação do RETOMAR, continua pausado', () async {
      expect(await gravador.pausar(), isTrue);
      tobias.responde = false;
      expect(await gravador.retomar(), isFalse);
      expect(gravador.pausado.value, isTrue);
    });

    test('confirmação atrasada ainda vale: a tela segue o aparelho', () async {
      tobias.responde = false;
      expect(await gravador.pausar(), isFalse);
      tobias.confirmar(StatusTobias.pausado); // chega depois do prazo
      await Future<void>.delayed(Duration.zero);
      expect(gravador.pausado.value, isTrue);
    });

    test('ts_ms não inclui o tempo parado e a bola continua', () async {
      await lances(4);
      await gravador.pausar();
      relogio.ms += 10 * 60 * 1000; // dez minutos de pausa
      await gravador.retomar();
      await lances(6);
      await _ate(gravador, 10);
      await gravador.encerrar();

      final s = (await gravador.fila.todas()).single;
      expect([for (final l in s.lances) l.bola], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

      final ts = [for (final l in s.lances) l.tsMs];
      // Só tempo de treino: 3,1 s por lance, a pausa não entra.
      expect(ts, [for (var i = 1; i <= 10; i++) i * 3100]);

      // A contagem do firmware também atravessou a pausa (mesma sessão).
      expect(s.lances[4].idLanceFirmware, endsWith('-5'));
      expect(s.lances[9].idLanceFirmware, endsWith('-10'));
      expect(s.encerradaEm, isNotNull);
    });
  });

  test('sessão vai para o disco antes de o TREINO: sair', () async {
    final tobias = _TobiasFalso();
    String? naHoraDoTreino;
    tobias.aoReceber = (c) async {
      if (c.startsWith('TREINO')) {
        naHoraDoTreino = (await SharedPreferences.getInstance()).getString(
          FilaSessoes.chave,
        );
      }
    };
    final gravador = GravadorSessao(
      sessao: _sessao(),
      fila: FilaSessoes(),
      transport: tobias,
    );
    await gravador.iniciar();

    expect(naHoraDoTreino, isNotNull);
    expect(naHoraDoTreino, contains(gravador.uuidSessao));
  });

  test('cada lance vai para o disco quando chega, não no fim', () async {
    final tobias = _TobiasFalso();
    final gravador = GravadorSessao(
      sessao: _sessao(),
      fila: FilaSessoes(),
      transport: tobias,
    );
    await gravador.iniciar();

    for (var n = 1; n <= 3; n++) {
      tobias.lance();
      await _ate(gravador, n);
      final noDisco = jsonDecode(
        (await SharedPreferences.getInstance()).getString(FilaSessoes.chave)!,
      );
      expect((noDisco['sessoes'][0]['lances'] as List), hasLength(n));
    }
  });

  test('lances além do total da sessão são ignorados (o simulador não para)', () async {
    final tobias = _TobiasFalso();
    final gravador = GravadorSessao(
      sessao: _sessao(lances: 3),
      fila: FilaSessoes(),
      transport: tobias,
    );
    await gravador.iniciar();
    for (var i = 0; i < 5; i++) {
      tobias.lance();
    }
    await _ate(gravador, 3);
    await gravador.encerrar();

    expect((await gravador.fila.todas()).single.lances, hasLength(3));
    expect(gravador.lancesRestantes, 0);
  });

  test('formato gravado: chaves da API, datas com fuso, ângulo intacto', () async {
    final tobias = _TobiasFalso();
    final gravador = GravadorSessao(
      sessao: _sessao(dificuldade: 12.345),
      fila: FilaSessoes(),
      transport: tobias,
      agora: () => DateTime.utc(2026, 10, 1, 11, 15),
    );
    await gravador.iniciar();
    tobias.lance(angulo: 61.4);
    tobias.lance(resultado: 'erro');
    await _ate(gravador, 2);
    await gravador.encerrar();

    final bruto = (await SharedPreferences.getInstance()).getString(
      FilaSessoes.chave,
    )!;
    final s = (jsonDecode(bruto)['sessoes'] as List).single as Map;

    expect(s.keys.toSet(), {
      'uuid_sessao',
      'treino_versao_id',
      'dificuldade',
      'iniciada_em',
      'encerrada_em',
      'sincronizada',
      // Locais, da etapa 5 (não vão no corpo do envio).
      'pontuacao_servidor',
      'falha',
      // Local, da etapa 7 (nome do treino para o histórico).
      'treino_titulo',
      // Local: o dono da sessão no aparelho (não vai no envio).
      'usuario_id',
      'lances',
    });
    final envio = (await gravador.fila.todas()).single.paraEnvio();
    expect(envio.containsKey('usuario_id'), isFalse);
    expect((s['lances'] as List).first.keys.toSet(), {
      'uuid_lance',
      'id_lance_firmware',
      'bola',
      'resultado',
      'classe',
      'knockout',
      'angulo',
      'ts_ms',
    });
    expect(s['iniciada_em'], '2026-10-01T11:15:00.000Z');
    expect(DateTime.parse(s['iniciada_em'] as String).isUtc, isTrue);
    expect(s['encerrada_em'], endsWith('Z'));
    // A dificuldade fica com 1 casa, como foi ao firmware.
    expect(s['dificuldade'], 12.3);
    // O ângulo chega ao disco com o mesmo texto que veio do firmware.
    expect(bruto, contains('"angulo":61.4'));
    expect(bruto, contains('"angulo":0.0'));
    expect(s['sincronizada'], isFalse);
  });

  test('acima de 20 pendentes, descarta as mais antigas e registra em log', () async {
    final logs = <String>[];
    final printOriginal = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null) logs.add(m);
    };
    try {
      final fila = FilaSessoes();
      for (var i = 1; i <= 22; i++) {
        await fila.abrir(
          SessaoLocal(
            uuidSessao: 'sessao-$i',
            treinoVersaoId: 1,
            dificuldade: 0,
            iniciadaEm: isoComFuso(DateTime.utc(2026, 10, i)),
          ),
        );
      }

      final restantes = await (await _matarEReabrir()).aguardandoEnvio();
      expect(restantes, hasLength(20));
      expect(restantes.first.uuidSessao, 'sessao-3');
      expect(restantes.last.uuidSessao, 'sessao-22');
      expect(logs.where((l) => l.contains('descartada')), hasLength(2));
      expect(logs.first, contains('sessao-1'));
    } finally {
      debugPrint = printOriginal;
    }
  });
}
