import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/mock_data.dart';
import 'package:smart_tennis_arena_mobile/data/models.dart';
import 'package:smart_tennis_arena_mobile/screens/sessao/em_andamento_screen.dart';
import 'package:smart_tennis_arena_mobile/state/device_state.dart';
import 'package:smart_tennis_arena_mobile/state/sessao_ativa.dart';
import 'package:smart_tennis_arena_mobile/transport/ble_transport.dart';
import 'package:smart_tennis_arena_mobile/transport/device_transport.dart';

/// Um treino como a API devolve em `GET /v1/drills`, com valores que não
/// existem em nenhum treino do mock (para o teste não passar por acaso).
const _treinoDaApi = {
  'id': 41,
  'titulo': 'Treino real da API',
  'descricao': 'Vindo do backend',
  'escopo': 'pessoal',
  'owner_id': 1,
  'origem_id': null,
  'versao_atual': {
    'id': 1234,
    'numero': 3,
    'nivel': 'dificil',
    'qtd_lances': 23,
    'intervalo_ms': 2500,
    'falas_tobias': true,
    'publicado_em': '2026-11-04T19:00:00Z',
  },
};

Drill _drillDaApi() => PaginaTreinos.fromJson({
  'items': [_treinoDaApi],
  'total': 1,
}).itens.single;

/// Tobias falso que confirma PAUSAR/RETOMAR (ou não, com [responde]).
class _TobiasFalso implements DeviceTransport {
  final _estados = StreamController<StatusTobias>.broadcast();
  final comandos = <String>[];
  var responde = true;

  @override
  Stream<ImpactEvent> get events => const Stream.empty();

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
    comandos.add(c);
    if (!responde) return;
    if (c == 'PAUSAR') _estados.add(StatusTobias.pausado);
    if (c == 'RETOMAR') _estados.add(StatusTobias.retomado);
  }

  @override
  Future<DeviceStatus> status() async =>
      const DeviceStatus(nome: 'TOBIAS', conectado: true, bateria: 90);

  @override
  Future<void> disconnect() async {}
}

void main() {
  group('comando TREINO', () {
    test('leva quantidade, intervalo em ms e calibração do treino', () {
      expect(
        montarComando(
          DeviceCommand.iniciarSessao,
          lances: 23,
          intervaloMs: 2500,
          calibracao: 2.5,
        ),
        'TREINO:23:2500:2.5\n',
      );
    });

    test('calibração zero vai como 0.0', () {
      expect(
        montarComando(DeviceCommand.iniciarSessao, lances: 10, intervaloMs: 4000),
        'TREINO:10:4000:0.0\n',
      );
    });

    test('pausar e retomar têm comando próprio; só finalizar manda STOP', () {
      expect(montarComando(DeviceCommand.pausar), 'PAUSAR\n');
      expect(
        montarComando(DeviceCommand.retomar, lances: 23, intervaloMs: 2500),
        'RETOMAR\n',
      );
      expect(montarComando(DeviceCommand.finalizar), 'STOP\n');
    });
  });

  group('interpretador BLE', () {
    test('PAUSADO e RETOMADO viram estados, não lances', () async {
      final ble = BleTransport();
      final estados = <StatusTobias>[];
      final lances = <ImpactEvent>[];
      final s1 = ble.estados.listen(estados.add);
      final s2 = ble.events.listen(lances.add);

      ble.interpretarLinha('{"status":"PAUSADO","bola_atual":4,"total":10}');
      ble.interpretarLinha('{"status":"RETOMADO","bola_atual":4,"total":10}');
      await Future<void>.delayed(Duration.zero);

      expect(estados, [StatusTobias.pausado, StatusTobias.retomado]);
      expect(lances, isEmpty);
      await s1.cancel();
      await s2.cancel();
    });

    test('status desconhecido ou malformado não quebra o que vem depois', () async {
      final ble = BleTransport();
      final estados = <StatusTobias>[];
      final lances = <ImpactEvent>[];
      final s1 = ble.estados.listen(estados.add);
      final s2 = ble.events.listen(lances.add);

      for (final linha in [
        '{"status":"QUALQUER_COISA_NOVA","resultado":"x","angulo":"y"}',
        '{"status":42}',
        '{"status":null}',
        '{"status":"PONG","modo":"PAUSADO","bola_atual":4}',
        'isto não é json',
        '[1,2,3]',
      ]) {
        ble.interpretarLinha(linha);
      }
      ble.interpretarLinha(
        '{"tipo":"TREINO","bola":5,"total":10,"resultado":"acerto",'
        '"classe":"medio","knockout":false,"angulo":41.2,"t_ms":9000,'
        '"id_lance":"L-9000-5"}',
      );
      ble.interpretarLinha('{"status":"PAUSADO","bola_atual":5,"total":10}');
      await Future<void>.delayed(Duration.zero);

      expect(lances, hasLength(1));
      expect(lances.single.aPkG, 41.2);
      expect(estados, [StatusTobias.pausado]);
      await s1.cancel();
      await s2.cancel();
    });
  });

  group('tela em andamento: pausa', () {
    Future<void> abrir(WidgetTester tester, _TobiasFalso tobias) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      final sessao = SessaoAtiva.iniciar(_drillDaApi(), dificuldade: 0);
      await tester.pumpWidget(
        MaterialApp(
          home: EmAndamentoScreen(
            sessao: sessao,
            fila: FilaSessoes(),
            transport: tobias,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    // O texto da falha está sempre na árvore (reserva a altura do cartão);
    // o que muda é se aparece.
    bool falhaVisivel(WidgetTester tester) => tester
        .widget<Visibility>(find.byKey(const ValueKey('cartao-falha')))
        .visible;

    Future<void> fechar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('com confirmação, vai para pausado e volta', (tester) async {
      final tobias = _TobiasFalso();
      await abrir(tester, tobias);

      await tester.tap(find.text('Pausar'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Continuar'), findsOneWidget);
      expect(falhaVisivel(tester), isFalse);

      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Pausar'), findsOneWidget);

      await fechar(tester);
      expect(tobias.comandos, ['TREINO:23:2500:0.0', 'PAUSAR', 'RETOMAR', 'STOP']);
    });

    testWidgets('sem confirmação em 1,5 s, não pausa e avisa', (tester) async {
      final tobias = _TobiasFalso()..responde = false;
      await abrir(tester, tobias);

      await tester.tap(find.text('Pausar'));
      await tester.pump();
      // Esperando: a tela não foi para pausado, e Finalizar segue disponível.
      expect(find.text('Continuar'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Finalizar sessão'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1400));
      expect(falhaVisivel(tester), isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Pausar'), findsOneWidget);
      expect(find.text('Continuar'), findsNothing);
      expect(falhaVisivel(tester), isTrue);
      expect(
        find.textContaining('O comando de pausa não foi confirmado'),
        findsOneWidget,
      );

      // Tentar de novo limpa a mensagem; a resposta agora vem.
      tobias.responde = true;
      await tester.tap(find.text('Pausar'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Continuar'), findsOneWidget);
      expect(falhaVisivel(tester), isFalse);

      await fechar(tester);
      expect(tobias.comandos.where((c) => c.startsWith('TREINO')), hasLength(1));
    });
  });

  test('treino da API traz o id da versão atual', () {
    final drill = _drillDaApi();
    expect(drill.versaoId, 1234);
    expect(drill.lances, 23);
    expect(drill.intervaloExatoMs, 2500);
  });

  group('SessaoAtiva', () {
    test('congela versão, lances, intervalo e dificuldade no início', () {
      final sessao = SessaoAtiva.iniciar(_drillDaApi(), dificuldade: 2.5);

      expect(sessao.titulo, 'Treino real da API');
      expect(sessao.treinoVersaoId, 1234);
      expect(sessao.lances, 23);
      expect(sessao.intervaloMs, 2500);
      expect(sessao.dificuldade, 2.5);
    });

    test('não acompanha uma edição do treino feita depois do início', () {
      final sessao = SessaoAtiva.iniciar(_drillDaApi(), dificuldade: 0);

      // O treino é editado: a API passa a devolver a versão 1235.
      final editado = PaginaTreinos.fromJson({
        'items': [
          {
            ..._treinoDaApi,
            'versao_atual': <String, dynamic>{
              ...(_treinoDaApi['versao_atual']! as Map<String, Object?>),
              'id': 1235,
              'qtd_lances': 5,
            },
          },
        ],
        'total': 1,
      }).itens.single;

      expect(editado.versaoId, 1235);
      expect(sessao.treinoVersaoId, 1234);
      expect(sessao.lances, 23);
    });

    test('recusa treino sem versão (dados de exemplo)', () {
      expect(
        () => SessaoAtiva.iniciar(Mock.reacaoRapida, dificuldade: 0),
        throwsArgumentError,
      );
    });
  });

  testWidgets(
    'tela em andamento mostra o treino real e manda o TREINO dele',
    (tester) async {
      // Captura o que o simulador registra. O debugPrint tem de voltar ao
      // original ANTES do fim do corpo do teste (o Flutter confere), por
      // isso o try/finally e não um addTearDown.
      final comandos = <String>[];
      final printOriginal = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {
        if (m != null) comandos.add(m);
      };
      DeviceState.simulador.value = true;
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      final fila = FilaSessoes();
      try {
        final sessao = SessaoAtiva.iniciar(_drillDaApi(), dificuldade: 2.5);
        await tester.pumpWidget(
          MaterialApp(home: EmAndamentoScreen(sessao: sessao, fila: fila)),
        );
        // O TREINO só sai depois de a sessão ser gravada na fila.
        await tester.pump();
        await tester.pump();

        final gravada = (await fila.todas()).single;
        expect(gravada.treinoVersaoId, 1234);
        expect(gravada.dificuldade, 2.5);

        expect(find.text('Treino real da API'), findsOneWidget);
        expect(find.textContaining('23 lances'), findsOneWidget);
        expect(find.text('Reação rápida'), findsNothing);
        expect(
          comandos,
          contains('[Simulador] comando (não enviado): TREINO:23:2500:2.5'),
        );

        // Desmonta a tela (para os timers e manda o STOP).
        await tester.pumpWidget(const SizedBox());
        await tester.pump(); // o STOP sai dentro do encerrar(), assíncrono
        expect(comandos.last, '[Simulador] comando (não enviado): STOP');
        expect((await fila.todas()).single.encerradaEm, isNotNull);
      } finally {
        debugPrint = printOriginal;
        DeviceState.simulador.value = false;
      }
    },
  );
}
