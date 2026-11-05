import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/detalhe_sessao.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/models.dart';
import 'package:smart_tennis_arena_mobile/data/resumo_sessao.dart';
import 'package:smart_tennis_arena_mobile/screens/historico/detalhe_screen.dart';
import 'package:smart_tennis_arena_mobile/widgets/cards.dart';

LanceLocal _lance(int bola, String resultado, num angulo) => LanceLocal(
  uuidLance: 'l-$bola',
  idLanceFirmware: null,
  bola: bola,
  resultado: resultado,
  // Classe ERRADA de propósito: a faixa tem de vir do ângulo.
  classe: 'medio',
  knockout: false,
  angulo: angulo,
  tsMs: bola * 3000,
);

/// Dificuldade 0: médio a partir de 38,0°, KO a partir de 58,0°. Lances
/// gravados FORA da ordem da bola, para provar que a tela ordena.
SessaoLocal _sessao({bool sincronizada = false, int? servidor}) => SessaoLocal(
  uuidSessao: 'det',
  treinoVersaoId: 1,
  dificuldade: 0,
  iniciadaEm: '2026-09-19T15:00:00.000Z',
  sincronizada: sincronizada,
  pontuacaoServidor: servidor,
  treinoTitulo: 'Reação rápida',
  lances: [
    _lance(3, 'acerto', 61.5), // KO
    _lance(1, 'acerto', 45.0), // médio
    _lance(4, 'erro', 0.0), // sem impacto
    _lance(2, 'acerto', 30.0), // fraco
    _lance(5, 'acerto', 58.0), // KO (no teto)
    _lance(6, 'acerto', 52.4), // médio
  ],
);

void main() {
  group('lances do detalhe', () {
    test('na ordem da bola, com a faixa pelo ângulo', () {
      final l = lancesDoDetalhe(_sessao());

      expect([for (final s in l) s.n], [1, 2, 3, 4, 5, 6]);
      expect(
        [for (final s in l) s.faixa],
        ['Médio', 'Fraco', 'KO', 'Sem impacto', 'KO', 'Médio'],
      );
      expect(
        [for (final s in l) s.resultado],
        [
          ShotResult.acerto,
          ShotResult.acerto,
          ShotResult.ko,
          ShotResult.erro,
          ShotResult.ko,
          ShotResult.acerto,
        ],
      );
    });

    test('mesmas faixas do resumo: as duas telas não discordam', () {
      final s = _sessao();
      final l = lancesDoDetalhe(s);
      final r = ResumoSessao.de(s);
      int conta(String f) => l.where((x) => x.faixa == f).length;

      expect(conta('Fraco'), r.fracos);
      expect(conta('Médio'), r.medios);
      expect(conta('KO'), r.kos);
      expect(conta('Sem impacto'), r.erros);
    });

    test('a soma dos pontos dos lances bate com a pontuação da sessão', () {
      final s = _sessao();
      final soma = lancesDoDetalhe(s).fold(0, (a, l) => a + l.pontos);
      expect(soma, s.pontuar().pontuacaoTotal);
      expect(soma, greaterThan(0));
    });

    test('erro: −20 e sem ângulo', () {
      final erro = lancesDoDetalhe(_sessao()).singleWhere((l) => l.n == 4);
      expect(erro.pontos, -20);
      expect(erro.angulo, isNull);
      expect(erro.faixa, 'Sem impacto');
    });

    test('filtros: Todos, Erros e KO', () {
      final l = lancesDoDetalhe(_sessao());
      expect(filtrarLances(l, FiltroLances.todos), hasLength(6));
      expect([for (final s in filtrarLances(l, FiltroLances.erros)) s.n], [4]);
      expect([for (final s in filtrarLances(l, FiltroLances.kos)) s.n], [3, 5]);
    });

    test('título com a data da sessão', () {
      final s = _sessao();
      final dia = DateTime.parse(s.iniciadaEm).toLocal().day;
      expect(tituloDoDetalhe(s), 'Sessão de $dia set');
    });
  });

  group('tela', () {
    setUp(() {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> abrir(WidgetTester tester, FilaSessoes fila, String uuid) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: DetalheScreen(uuidSessao: uuid, fila: fila)),
      );
      await tester.pump();
      await tester.pump();
    }

    List<String> titulos(WidgetTester tester) => [
      for (final e in find.textContaining('Lance 0').evaluate())
        (e.widget as Text).data!,
    ];

    testWidgets('abre pelo uuid_sessao e lista os lances na ordem da bola', (
      tester,
    ) async {
      final fila = FilaSessoes();
      await fila.abrir(_sessao());
      await abrir(tester, fila, 'det');

      expect(find.text('Lances (6)'), findsOneWidget);
      expect(find.text('Reação rápida'), findsOneWidget);
      expect(find.text('Pendente'), findsOneWidget);
      expect(titulos(tester), [
        'Lance 01 · Médio',
        'Lance 02 · Fraco',
        'Lance 03 · KO',
        'Lance 04 · Sem impacto',
        'Lance 05 · KO',
        'Lance 06 · Médio',
      ]);
      // Grau, não g; erro sem ângulo; KO derruba o boneco.
      expect(find.text('45,0°'), findsOneWidget);
      expect(find.text('61,5° · derrubou o boneco'), findsOneWidget);
      expect(find.text('sem impacto registrado'), findsOneWidget);
      expect(find.text('−20'), findsOneWidget);
      expect(find.textContaining(' g'), findsNothing);
      expect(find.text('Forte'), findsNothing);
    });

    testWidgets('filtros trocam a lista; sem resultado, estado próprio', (
      tester,
    ) async {
      final fila = FilaSessoes();
      await fila.abrir(_sessao());
      // Uma sem erro nenhum, para o filtro vazio.
      await fila.abrir(
        SessaoLocal(
          uuidSessao: 'sem-erro',
          treinoVersaoId: 1,
          dificuldade: 0,
          iniciadaEm: '2026-09-20T15:00:00.000Z',
          lances: [_lance(1, 'acerto', 45.0)],
        ),
      );
      await abrir(tester, fila, 'det');

      await tester.tap(find.text('Erros'));
      await tester.pump();
      expect(titulos(tester), ['Lance 04 · Sem impacto']);

      await tester.tap(find.text('KO'));
      await tester.pump();
      expect(titulos(tester), ['Lance 03 · KO', 'Lance 05 · KO']);

      await tester.tap(find.text('Todos'));
      await tester.pump();
      expect(titulos(tester), hasLength(6));

      await abrir(tester, fila, 'sem-erro');
      await tester.tap(find.text('Erros'));
      await tester.pump();
      expect(titulos(tester), isEmpty);
      expect(find.text('Nenhum erro nesta sessão.'), findsOneWidget);
    });

    testWidgets('sincronizada: pontuação do servidor, sem selo', (tester) async {
      final fila = FilaSessoes();
      final s = _sessao(sincronizada: true, servidor: 4321);
      await fila.abrir(s);
      await abrir(tester, fila, 'det');

      expect(find.text('4.321'), findsOneWidget);
      expect(find.text('Pendente'), findsNothing);
      // Os pontos de cada lance seguem a regra local.
      expect(find.byType(ShotRow), findsNWidgets(6));
    });

    testWidgets('sessão inexistente: o estado de não encontrada', (tester) async {
      await abrir(tester, FilaSessoes(), 'nao-existe');
      expect(find.text('Sessão não encontrada neste aparelho.'), findsOneWidget);
    });
  });
}
