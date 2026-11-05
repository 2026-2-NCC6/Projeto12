import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/resumo_sessao.dart';
import 'package:smart_tennis_arena_mobile/screens/historico/historico_screen.dart';
import 'package:smart_tennis_arena_mobile/screens/sessao/resumo_screen.dart';

var _n = 0;

LanceLocal _acerto(num angulo) {
  _n++;
  return LanceLocal(
    uuidLance: 'l-$_n',
    idLanceFirmware: null,
    bola: _n,
    resultado: 'acerto',
    classe: 'medio',
    knockout: false,
    angulo: angulo,
    tsMs: _n * 3000,
  );
}

LanceLocal _erro() {
  _n++;
  return LanceLocal(
    uuidLance: 'l-$_n',
    idLanceFirmware: null,
    bola: _n,
    resultado: 'erro',
    classe: 'sem_impacto',
    knockout: false,
    angulo: 0.0,
    tsMs: _n * 3000,
  );
}

/// Sessão do dia [dia] de novembro, às 10h UTC. [angulos] viram acertos.
SessaoLocal _sessao(
  String uuid,
  int dia, {
  List<num> angulos = const [45.0],
  int erros = 0,
  bool sincronizada = false,
  int? servidor,
  String? titulo = 'Reação rápida',
}) {
  _n = 0;
  return SessaoLocal(
    uuidSessao: uuid,
    treinoVersaoId: 1,
    dificuldade: 0,
    iniciadaEm: '2026-11-${dia.toString().padLeft(2, '0')}T10:00:00.000Z',
    sincronizada: sincronizada,
    pontuacaoServidor: servidor,
    treinoTitulo: titulo,
    lances: [for (final a in angulos) _acerto(a), for (var i = 0; i < erros; i++) _erro()],
  );
}

int _local(SessaoLocal s) => s.pontuar().pontuacaoTotal;

void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  group('comparação com a sessão anterior (RF12)', () {
    test('sem sessão anterior: nula (a tela não mostra a linha)', () {
      final unica = _sessao('a', 3);
      expect(variacaoSobreAnterior(unica, [unica]), isNull);
    });

    test('a anterior é a mais recente ANTES desta, não a última da fila', () {
      final d1 = _sessao('d1', 1, angulos: [30.0]);
      final d2 = _sessao('d2', 2, angulos: [45.0, 45.0]);
      final d3 = _sessao('d3', 3, angulos: [60.0]);
      final todas = [d3, d1, d2];

      expect(variacaoSobreAnterior(d2, todas), _local(d2) - _local(d1));
      expect(variacaoSobreAnterior(d3, todas), _local(d3) - _local(d2));
      expect(variacaoSobreAnterior(d1, todas), isNull);
    });

    test('sessão sem lances não conta como anterior', () {
      final d1 = _sessao('d1', 1, angulos: [30.0]);
      final vazia = _sessao('vazia', 2, angulos: []);
      final d3 = _sessao('d3', 3);

      expect(variacaoSobreAnterior(d3, [d1, vazia, d3]), _local(d3) - _local(d1));
    });

    test('pendente também serve de anterior', () {
      final pendente = _sessao('p', 1, angulos: [30.0]);
      final atual = _sessao('a', 2);
      expect(variacaoSobreAnterior(atual, [pendente, atual]), isNotNull);
    });

    test('usa a pontuação exibida: a oficial do servidor quando existe', () {
      final anterior = _sessao('a', 1, sincronizada: true, servidor: 100);
      final atual = _sessao('b', 2, sincronizada: true, servidor: 123);
      expect(variacaoSobreAnterior(atual, [anterior, atual]), 23);
    });

    test('texto: uma linha, com sinal', () {
      expect(textoVariacao(23), '+23 em relação à sessão anterior');
      expect(textoVariacao(-12), '−12 em relação à sessão anterior');
      expect(textoVariacao(1500), '+1.500 em relação à sessão anterior');
      expect(textoVariacao(0), 'Mesma pontuação da sessão anterior');
    });
  });

  group('histórico local', () {
    test('da mais recente para a mais antiga, sem as vazias, com as separadas', () async {
      final fila = FilaSessoes();
      await fila.abrir(_sessao('d1', 1));
      await fila.abrir(_sessao('d3', 3));
      await fila.abrir(_sessao('vazia', 4, angulos: []));
      await fila.abrir(_sessao('d2', 2));
      await fila.separar('d2', 'payload_invalido');

      final uuids = [for (final s in await fila.historico()) s.uuidSessao];
      expect(uuids, ['d3', 'd2', 'd1']);
    });

    test('cartão: data local, treino, pontuação exibida e precisão', () {
      final s = _sessao(
        'x',
        19,
        angulos: [45.0, 45.0, 45.0],
        erros: 1,
        sincronizada: true,
        servidor: 999,
      );
      final item = itemDoHistorico(s);
      final local = DateTime.parse(s.iniciadaEm).toLocal();

      expect(item.dia, local.day);
      expect(item.mes, 'NOV');
      expect(item.drillTitulo, 'Reação rápida');
      expect(item.pontos, 999);
      expect(item.precisao, 75);
      expect(item.lances, 4);
      expect(item.sincronizada, isTrue);
      expect(item.separada, isFalse);
    });

    test('sessão antiga, sem nome do treino gravado: "Treino"', () {
      expect(itemDoHistorico(_sessao('x', 1, titulo: null)).drillTitulo, 'Treino');
    });

    test('o nome do treino fica no aparelho: não vai no envio', () {
      expect(_sessao('x', 1).paraEnvio().containsKey('treino_titulo'), isFalse);
      expect(_sessao('x', 1).toJson()['treino_titulo'], 'Reação rápida');
    });
  });

  group('telas', () {
    void tamanho(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('histórico lista as sessões, marca as pendentes e avisa que é local', (
      tester,
    ) async {
      tamanho(tester);
      final fila = FilaSessoes();
      await fila.abrir(_sessao('d1', 1, titulo: 'Sequência dupla', sincronizada: true));
      await fila.abrir(_sessao('d2', 2, titulo: 'Reação turbo'));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HistoricoScreen(fila: fila))));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Últimas sessões deste aparelho'), findsOneWidget);
      final turbo = tester.getTopLeft(find.text('Reação turbo'));
      final dupla = tester.getTopLeft(find.text('Sequência dupla'));
      expect(turbo.dy, lessThan(dupla.dy), reason: 'a mais recente primeiro');
      expect(find.text('Pendente'), findsOneWidget);
      expect(find.text('Sincronizado'), findsOneWidget);
      // Sem filtro por período.
      expect(find.text('Este mês'), findsNothing);
    });

    testWidgets('histórico vazio', (tester) async {
      tamanho(tester);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HistoricoScreen(fila: FilaSessoes()))),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Nenhuma sessão neste aparelho ainda.'), findsOneWidget);
    });

    Future<void> resumo(WidgetTester tester, FilaSessoes fila, String uuid) async {
      tamanho(tester);
      await tester.pumpWidget(
        MaterialApp(home: ResumoScreen(uuidSessao: uuid, treino: 'Treino X', fila: fila)),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('resumo da primeira sessão: sem linha de comparação', (tester) async {
      final fila = FilaSessoes();
      await fila.abrir(_sessao('d1', 1));
      await resumo(tester, fila, 'd1');

      expect(find.textContaining('sessão anterior'), findsNothing);
    });

    testWidgets('resumo da segunda: uma linha com a diferença', (tester) async {
      final fila = FilaSessoes();
      final d1 = _sessao('d1', 1, angulos: [30.0]);
      final d2 = _sessao('d2', 2, angulos: [45.0, 60.0]);
      await fila.abrir(d1);
      await fila.abrir(d2);
      await resumo(tester, fila, 'd2');

      expect(
        find.text(textoVariacao(_local(d2) - _local(d1))),
        findsOneWidget,
      );
      expect(find.textContaining('sessão anterior'), findsOneWidget);
    });
  });
}
