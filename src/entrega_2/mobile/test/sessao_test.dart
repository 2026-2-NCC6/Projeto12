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

    test('retomar repete o mesmo TREINO; pausar e finalizar mandam STOP', () {
      expect(
        montarComando(DeviceCommand.retomar, lances: 23, intervaloMs: 2500),
        'TREINO:23:2500:0.0\n',
      );
      expect(montarComando(DeviceCommand.pausar), 'STOP\n');
      expect(montarComando(DeviceCommand.finalizar), 'STOP\n');
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
