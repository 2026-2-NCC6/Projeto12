import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/resumo_sessao.dart';
import 'package:smart_tennis_arena_mobile/screens/sessao/resumo_screen.dart';
import 'package:smart_tennis_arena_mobile/widgets/cards.dart';

var _n = 0;

LanceLocal _lance(String resultado, num angulo, String classe) {
  _n++;
  return LanceLocal(
    uuidLance: 'l-$_n',
    idLanceFirmware: null,
    bola: _n,
    resultado: resultado,
    classe: classe,
    knockout: false,
    angulo: angulo,
    tsMs: _n * 3000,
  );
}

LanceLocal _erro() => _lance('erro', 0.0, 'sem_impacto');

/// O caso "sessao-longa-misturando-tudo" dos golden fixtures (dificuldade
/// 5,0; 712 pontos, 2 KOs, sequência 4), com classes de exibição.
SessaoLocal _sessaoLonga() {
  _n = 0;
  return SessaoLocal(
    uuidSessao: 'longa',
    treinoVersaoId: 1,
    dificuldade: 5.0,
    iniciadaEm: '2026-10-01T11:15:00.000Z',
    lances: [
      _lance('acerto', 30.0, 'fraco'),
      _lance('acerto', 45.0, 'medio'),
      _lance('acerto', 63.0, 'forte'),
      _erro(),
      _erro(),
      _lance('acerto', 50.0, 'medio'),
      _lance('acerto', 62.9, 'forte'),
      _lance('acerto', 22.0, 'fraco'),
      _lance('acerto', 70.0, 'forte'),
      _erro(),
      _lance('acerto', 38.5, 'fraco'),
    ],
  );
}

SessaoLocal _sessao(List<LanceLocal> lances) => SessaoLocal(
  uuidSessao: 's',
  treinoVersaoId: 1,
  dificuldade: 0,
  iniciadaEm: '2026-10-01T11:15:00.000Z',
  lances: lances,
);

void main() {
  group('faixas de intensidade, pelo ângulo', () {
    test('invariante: fracos + médios + KO = acertos; acertos + erros = lances', () {
      // Dificuldade 2,0: médio a partir de 40,0°, KO a partir de 60,0°.
      // A `classe` de cada lance está ERRADA de propósito (tudo "medio",
      // como o simulador carimba): as faixas não podem depender dela.
      _n = 0;
      final s = SessaoLocal(
        uuidSessao: 'faixas',
        treinoVersaoId: 1,
        dificuldade: 2.0,
        iniciadaEm: '2026-11-05T10:00:00.000Z',
        lances: [
          _lance('acerto', 25.0, 'medio'), // fraco
          _lance('acerto', 39.9, 'medio'), // fraco (logo abaixo do médio)
          _lance('acerto', 40.0, 'medio'), // médio (no limiar)
          _lance('acerto', 59.9, 'medio'), // médio (logo abaixo do KO)
          _lance('acerto', 60.0, 'medio'), // KO (no teto)
          _lance('acerto', 72.5, 'medio'), // KO
          _erro(),
          _erro(),
        ],
      );

      final r = ResumoSessao.de(s);

      expect((r.fracos, r.medios, r.kos), (2, 2, 2));
      expect(r.fracos + r.medios + r.kos, r.acertos);
      expect(r.acertos + r.erros, r.lances);
      expect(r.lances, s.lances.length);
      // O KO das faixas é o mesmo da pontuação.
      expect(r.kos, s.pontuar().kos);
    });

    test('a invariante vale também no caso golden', () {
      final r = ResumoSessao.de(_sessaoLonga());
      expect(r.fracos + r.medios + r.kos, r.acertos);
      expect(r.acertos + r.erros, r.lances);
    });
  });

  group('placar exibido', () {
    test('pendente: o local, mesmo que já haja número do servidor', () {
      // Ex.: chegou lance depois do envio; o servidor pontuou outra versão.
      final s = _sessaoLonga()..pontuacaoServidor = 700;
      expect(ResumoSessao.de(s).pontuacaoTotal, 712);
    });

    test('sincronizada: o do servidor, que é o oficial', () {
      final s = _sessaoLonga()
        ..sincronizada = true
        ..pontuacaoServidor = 713;
      final r = ResumoSessao.de(s);
      expect(r.pontuacaoTotal, 713);
      // O que o servidor não devolve continua da regra local.
      expect(r.melhorSequencia, 4);
      expect(r.kos, 2);
    });

    test('sincronizada numa fila antiga, sem número do servidor: o local', () {
      final s = _sessaoLonga()..sincronizada = true;
      expect(ResumoSessao.de(s).pontuacaoTotal, 712);
    });
  });

  test('sessão mista: números conferidos à mão', () {
    final r = ResumoSessao.de(_sessaoLonga());

    // Regra oficial (golden "sessao-longa-misturando-tudo").
    expect(r.pontuacaoTotal, 712);
    expect(r.melhorSequencia, 4);
    expect(r.kos, 2);

    expect((r.lances, r.acertos, r.erros), (11, 8, 3));
    expect(r.precisao, closeTo(8 / 11, 1e-12));
    // Faixas pelo ângulo (médio a partir de 43,0°, KO a partir de 63,0°),
    // e não pela classe carimbada: 30/22/38,5 fracos; 45/50/62,9 médios
    // (62,9 é "forte" na classe, mas não chega ao KO); 63/70 KO.
    expect((r.fracos, r.medios, r.kos), (3, 3, 2));
    // (30 + 45 + 63 + 50 + 62,9 + 22 + 70 + 38,5) / 8 = 381,4 / 8
    expect(r.mediaAngulo, closeTo(47.675, 1e-9));
    expect(r.maxAngulo, 70.0);
    // Σ(a − 47,675)² = 2033,415 → σ = √(2033,415 / 8) = 15,9429…
    // 1 − 15,9429 / 47,675 = 0,6656…
    expect(r.consistencia, closeTo(0.66559, 1e-4));
  });

  test('sem acertos: média, máximo e consistência são indefinidos', () {
    _n = 0;
    final r = ResumoSessao.de(_sessao([_erro(), _erro()]));

    expect(r.consistencia, isNull);
    expect(r.mediaAngulo, isNull);
    expect(r.maxAngulo, isNull);
    expect(r.precisao, 0);
    expect(r.pontuacaoTotal, 0);
  });

  test('sessão sem lances: precisão também é indefinida', () {
    final r = ResumoSessao.de(_sessao([]));
    expect(r.precisao, isNull);
    expect(r.consistencia, isNull);
  });

  test('consistência: um acerto dá 1, iguais dão 1, dispersão enorme dá 0', () {
    expect(calcularConsistencia([45.0]), 1.0);
    expect(calcularConsistencia([40.0, 40.0, 40.0]), 1.0);
    // σ maior que a média: 1 − σ/μ < 0, limitado a 0.
    expect(calcularConsistencia([0.1, 0.1, 0.1, 100.0]), 0.0);
    expect(calcularConsistencia([0.0, 0.0]), isNull); // média 0
  });

  group('tela', () {
    setUp(() {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> abrir(WidgetTester tester, FilaSessoes fila, String uuid) async {
      tester.view.physicalSize = const Size(412, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ResumoScreen(uuidSessao: uuid, treino: 'Treino X', fila: fila),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('mostra os números da sessão e as pendentes', (tester) async {
      final fila = FilaSessoes();
      // Direto no corpo (e não em runAsync): a cadeia de gravações da fila
      // precisa viver no mesmo relógio falso que a tela.
      await fila.abrir(_sessaoLonga());
      await fila.abrir(_sessao([]));
      await abrir(tester, fila, 'longa');

      Finder card(String rotulo) => find.ancestor(
        of: find.text(rotulo),
        matching: find.byType(StatCard),
      );
      void valor(String rotulo, String esperado) => expect(
        find.descendant(of: card(rotulo), matching: find.text(esperado)),
        findsOneWidget,
        reason: rotulo,
      );

      expect(find.text('712'), findsOneWidget);
      expect(find.text('Treino X'), findsOneWidget);
      expect(find.text('pontos'), findsOneWidget);
      expect(find.text('11 lances · 8 acertos'), findsOneWidget);
      valor('Precisão', '73%');
      valor('Melhor sequência', '4');
      valor('KO', '2');
      valor('Erros', '3');
      valor('Fracos', '3');
      valor('Médios', '3');
      expect(find.text('Salvo no celular, aguardando envio'), findsOneWidget);
      expect(find.text('2 sessões na fila'), findsOneWidget);

      // Fora da tela (etapa 4b), embora continuem calculados.
      for (final fora in [
        'Fortes',
        'Consistência',
        'Ângulo médio',
        'Ângulo máximo',
        'Novo recorde pessoal',
      ]) {
        expect(find.text(fora), findsNothing, reason: fora);
      }
      expect(find.textContaining('Precisão estimada'), findsNothing);
    });

    testWidgets('sem lances, precisão é traço, não zero', (tester) async {
      final fila = FilaSessoes();
      await fila.abrir(_sessao([]));
      await abrir(tester, fila, 's');

      expect(find.text('—'), findsOneWidget);
      expect(find.text('1 sessão na fila'), findsOneWidget);
    });

    testWidgets('só erros: precisão 0%, definida', (tester) async {
      final fila = FilaSessoes();
      _n = 0;
      await fila.abrir(_sessao([_erro()]));
      await abrir(tester, fila, 's');

      expect(find.text('0%'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('separadas por erro: contagem à parte das pendentes', (
      tester,
    ) async {
      final fila = FilaSessoes();
      await fila.abrir(_sessaoLonga());
      await fila.abrir(_sessao([]));
      await fila.separar('s', 'payload_invalido');
      await abrir(tester, fila, 'longa');

      expect(find.text('1 sessão na fila'), findsOneWidget);
      expect(find.text('Não foi possível enviar'), findsOneWidget);
      expect(
        find.text('1 sessão com erro, guardada no celular'),
        findsOneWidget,
      );
    });

    testWidgets('sem separadas, sem aviso de erro', (tester) async {
      final fila = FilaSessoes();
      await fila.abrir(_sessao([]));
      await abrir(tester, fila, 's');

      expect(find.text('Não foi possível enviar'), findsNothing);
    });

    testWidgets('pendente mostra o placar local; sincronizada, o do servidor', (
      tester,
    ) async {
      final fila = FilaSessoes();
      await fila.abrir(_sessaoLonga());
      await abrir(tester, fila, 'longa');
      expect(find.text('712'), findsOneWidget);

      // O envio termina com a tela aberta. Número do servidor diferente de
      // propósito, para ver que é ele que aparece (sem alerta nenhum).
      final enviados = await fila.prepararEnvio();
      await fila.aplicarRespostas(enviados, const [
        RespostaSessao(
          uuidSessao: 'longa',
          situacao: 'inserida',
          pontuacaoTotal: 713,
        ),
      ]);
      await tester.pump();
      await tester.pump();

      expect(find.text('713'), findsOneWidget);
      expect(find.text('712'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('diverg'), findsNothing);
    });

    testWidgets('sessão que não está na fila', (tester) async {
      await abrir(tester, FilaSessoes(), 'inexistente');
      expect(find.text('Sessão não encontrada neste aparelho.'), findsOneWidget);
    });
  });
}
