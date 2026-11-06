import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/ranking.dart';
import 'package:smart_tennis_arena_mobile/screens/ranking/ranking_screen.dart';
import 'package:smart_tennis_arena_mobile/state/app_settings.dart';
import 'package:smart_tennis_arena_mobile/theme/app_colors.dart';

const _aviso = 'Sua posição · você não aparece no ranking público';

Map<String, dynamic> _item(int posicao, String apelido, num valor, [int sessoes = 3]) =>
    {'posicao': posicao, 'apelido': apelido, 'valor': valor, 'sessoes': sessoes};

/// O `voce` como a API manda: um item com `oculto`.
Map<String, dynamic> _voce(
  int posicao,
  String apelido,
  num valor, {
  required bool oculto,
  int sessoes = 3,
}) => {..._item(posicao, apelido, valor, sessoes), 'oculto': oculto};

/// Lista de [n] jogadores com valores decrescentes a partir de [topo].
List<Map<String, dynamic>> _lista(int n, {num topo = 3000, num passo = 100}) => [
  for (var i = 0; i < n; i++) _item(i + 1, 'J${(i + 1).toString().padLeft(2, '0')}', topo - i * passo),
];

Map<String, dynamic> _resposta(
  String metrica, {
  List<Map<String, dynamic>>? itens,
  Map<String, dynamic>? voce,
}) => {
  'metrica': metrica,
  'periodo': {'de': '2026-10-07T15:00:00Z', 'ate': '2026-11-06T15:00:00Z'},
  'itens': itens ?? _lista(20),
  'voce': voce,
};

/// API falsa: guarda as métricas pedidas e responde o que [responder] mandar.
class _Api {
  _Api(this.responder);

  final FutureOr<http.Response> Function(String metrica) responder;
  final pedidas = <String>[];
  var acordou = 0;

  late final client = ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/health') {
        acordou++;
        return http.Response('{}', 200);
      }
      expect(req.url.path, '/v1/ranking');
      expect(req.headers['Authorization'], 'Bearer t');
      final m = req.url.queryParameters['metrica']!;
      pedidas.add(m);
      return responder(m);
    }),
  );
}

http.Response _ok(Map<String, dynamic> corpo) => http.Response(
  jsonEncode(corpo),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> _abrir(
  WidgetTester tester,
  _Api api, {
  MetricaRanking aba = MetricaRanking.pontos,
  Future<String?> Function()? lerToken,
  bool assentar = true,
}) async {
  // Tela alta: a lista inteira fica construída, sem rolagem nos testes.
  tester.view.physicalSize = const Size(390, 2600) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RankingScreen(
          aba: aba,
          api: api.client,
          lerToken: lerToken ?? () async => 't',
        ),
      ),
    ),
  );
  if (assentar) await tester.pumpAndSettle();
}

/// Toca no chip da aba. Com a fonte de teste (glifos quadrados, mais largos que
/// a Roboto), o último chip passa da borda e o ChipBar precisa rolar.
Future<void> _aba(WidgetTester tester, String rotulo) async {
  await tester.ensureVisible(find.text(rotulo));
  await tester.tap(find.text(rotulo));
}

void main() {
  // Roboto, como o app: a fonte padrão do teste tem glifos quadrados, bem
  // mais largos, e mediria um layout que não existe.
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Roboto-$peso.ttf'));
    }
    await loader.load();
  });

  group('formato do valor', () {
    test('pontos com ponto de milhar', () {
      expect(fmtValorRanking(MetricaRanking.pontos, 2538), '2.538');
      expect(fmtValorRanking(MetricaRanking.pontos, 95), '95');
    });

    test('frequência em dias, com singular', () {
      expect(fmtValorRanking(MetricaRanking.frequencia, 6), '6 dias');
      expect(fmtValorRanking(MetricaRanking.frequencia, 1), '1 dia');
    });

    test('evolução com sinal, inclusive negativa, e zero sem sinal', () {
      expect(fmtValorRanking(MetricaRanking.evolucao, 287.5), '+288%');
      expect(fmtValorRanking(MetricaRanking.evolucao, 100.0), '+100%');
      expect(fmtValorRanking(MetricaRanking.evolucao, -5.3), '−5%');
      expect(fmtValorRanking(MetricaRanking.evolucao, -66.7), '−67%');
      expect(fmtValorRanking(MetricaRanking.evolucao, 0.4), '0%');
      expect(fmtValorRanking(MetricaRanking.evolucao, -0.4), '0%');
    });
  });

  testWidgets('cada aba pede a sua métrica, com subtítulo e formato próprios', (
    tester,
  ) async {
    final api = _Api(
      (m) => _ok(
        _resposta(
          m,
          itens: switch (m) {
            'pontos' => _lista(5, topo: 2538),
            'frequencia' => _lista(5, topo: 6, passo: 1),
            _ => [_item(1, 'J01', 287.5), _item(2, 'J02', 12.0), _item(3, 'J03', -5.3)],
          },
        ),
      ),
    );
    await _abrir(tester, api);

    // Abre em Pontos.
    expect(api.pedidas, ['pontos']);
    expect(api.acordou, 1);
    expect(find.text('Soma de pontos nos últimos 30 dias.'), findsOneWidget);
    expect(find.text('2.538'), findsOneWidget);
    expect(find.text('Consistência'), findsNothing);

    await _aba(tester, 'Frequência');
    await tester.pumpAndSettle();
    expect(api.pedidas.last, 'frequencia');
    expect(find.text('Quem mais treinou nos últimos 7 dias.'), findsOneWidget);
    expect(find.text('6 dias'), findsOneWidget);

    await _aba(tester, 'Evolução');
    await tester.pumpAndSettle();
    expect(api.pedidas.last, 'evolucao');
    expect(
      find.text(
        'Quem mais evoluiu, comparando os últimos 30 dias com os 30 anteriores.',
      ),
      findsOneWidget,
    );
    expect(find.text('+288%'), findsOneWidget);
    expect(find.text('−5%'), findsOneWidget);

    // Negativo sem alarde: a mesma cor do positivo no mesmo tipo de degrau
    // (2º e 3º; o 1º tem fundo próprio), nada de vermelho.
    Color? cor(String t) => tester.widget<Text>(find.text(t)).style?.color;
    expect(cor('−5%'), cor('+12%'));
    expect(cor('−5%'), isNot(AppColors.textError));

    expect(api.pedidas, ['pontos', 'frequencia', 'evolucao']);
  });

  testWidgets('abre direto na aba pedida pela rota', (tester) async {
    final api = _Api((m) => _ok(_resposta(m)));
    await _abrir(tester, api, aba: MetricaRanking.evolucao);
    expect(api.pedidas, ['evolucao']);
  });

  group('a linha de quem usa o app', () {
    testWidgets('na lista: destacada no lugar dela, sem duplicar', (tester) async {
      final itens = _lista(20);
      itens[4] = _item(5, 'Eu', 2600);
      final api = _Api((m) => _ok(_resposta(m, itens: itens, voce: itens[4])));
      await _abrir(tester, api);

      expect(find.byKey(const ValueKey('voce-na-lista')), findsOneWidget);
      expect(find.byKey(const ValueKey('voce-fixado')), findsNothing);
      expect(find.text('Eu'), findsOneWidget);
      expect(find.text(_aviso), findsNothing);
      expect(find.text('Você · 3 sessões'), findsOneWidget);
    });

    testWidgets('no pódio: destacada no degrau, sem linha extra', (tester) async {
      final itens = _lista(20);
      itens[1] = _item(2, 'Eu', 2900);
      final api = _Api((m) => _ok(_resposta(m, itens: itens, voce: itens[1])));
      await _abrir(tester, api);

      expect(find.byKey(const ValueKey('voce-no-podio')), findsOneWidget);
      expect(find.text('2º · você'), findsOneWidget);
      expect(find.byKey(const ValueKey('voce-fixado')), findsNothing);
      expect(find.text('Eu'), findsOneWidget);
    });

    testWidgets('adulto fora dos 20: fixada no rodapé, só "Sua posição", sem duplicar', (
      tester,
    ) async {
      // Em 26º ele ESTÁ no ranking público, só não cabe nos 20: dizer que
      // "não aparece" seria falso.
      final api = _Api(
        (m) => _ok(_resposta(m, voce: _voce(26, 'Eu', 10, oculto: false, sessoes: 1))),
      );
      await _abrir(tester, api);

      final fixado = find.byKey(const ValueKey('voce-fixado'));
      expect(fixado, findsOneWidget);
      expect(find.descendant(of: fixado, matching: find.text('26')), findsOneWidget);
      expect(find.descendant(of: fixado, matching: find.text('Sua posição')), findsOneWidget);
      expect(find.text(_aviso), findsNothing);
      expect(find.textContaining('não aparece'), findsNothing);
      expect(find.byKey(const ValueKey('voce-na-lista')), findsNothing);
      expect(find.text('Eu'), findsOneWidget);

      // Fixada FORA da área que rola: separada da lista.
      expect(
        find.descendant(of: find.byType(ListView), matching: fixado),
        findsNothing,
      );
    });

    testWidgets('oculto, com posição que coincide com a de alguém visível: avisa', (
      tester,
    ) async {
      // A API posiciona o menor contra a lista de adultos: 5º, como o J05.
      final api = _Api(
        (m) => _ok(_resposta(m, voce: _voce(5, 'Juninho', 2650, oculto: true))),
      );
      await _abrir(tester, api);

      expect(find.text('J05'), findsOneWidget); // o 5º da lista pública
      final fixado = find.byKey(const ValueKey('voce-fixado'));
      expect(find.descendant(of: fixado, matching: find.text('5')), findsOneWidget);
      expect(find.descendant(of: fixado, matching: find.text(_aviso)), findsOneWidget);
      expect(find.text('Juninho'), findsOneWidget);
    });

    testWidgets('oculto abaixo dos 20 também avisa: a regra, não o corte', (
      tester,
    ) async {
      final api = _Api(
        (m) => _ok(_resposta(m, voce: _voce(25, 'Juninho', 40, oculto: true))),
      );
      await _abrir(tester, api);
      expect(find.text(_aviso), findsOneWidget);
    });

    testWidgets('sem o campo oculto (API antiga): texto neutro, nunca o aviso', (
      tester,
    ) async {
      final api = _Api((m) => _ok(_resposta(m, voce: _item(26, 'Eu', 10))));
      await _abrir(tester, api);
      expect(find.text('Sua posição'), findsOneWidget);
      expect(find.text(_aviso), findsNothing);
    });

    testWidgets('voce nulo: convite a treinar, sem posição nem zeros', (tester) async {
      final api = _Api((m) => _ok(_resposta(m, itens: _lista(5))));
      await _abrir(tester, api);

      expect(find.byKey(const ValueKey('convite')), findsOneWidget);
      expect(find.text('Você ainda não pontuou nos últimos 30 dias'), findsOneWidget);
      expect(find.text('Treinar'), findsOneWidget);
      expect(find.byKey(const ValueKey('voce-fixado')), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text(_aviso), findsNothing);

      await _aba(tester, 'Frequência');
      await tester.pumpAndSettle();
      expect(find.text('Você não treinou nos últimos 7 dias'), findsOneWidget);
      expect(find.text('0 dias'), findsNothing);
    });

    testWidgets('evolução sem o mínimo de sessões explica o motivo', (tester) async {
      final api = _Api((m) => _ok(_resposta(m, itens: _lista(5, topo: 50, passo: 5))));
      await _abrir(tester, api, aba: MetricaRanking.evolucao);

      expect(find.text('Você ainda não entra na evolução'), findsOneWidget);
      expect(find.textContaining('ao menos 3 sessões nos últimos 30 dias e 3 nos 30'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
    });
  });

  group('estados', () {
    testWidgets('carregando avisa que a primeira chamada pode demorar', (tester) async {
      final resposta = Completer<http.Response>();
      final api = _Api((_) => resposta.future);
      await _abrir(tester, api, assentar: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('primeira consulta pode levar até 30 s'), findsOneWidget);
      expect(api.acordou, 1, reason: 'acordarApi() antes da consulta');

      resposta.complete(_ok(_resposta('pontos')));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('J01'), findsOneWidget);
    });

    testWidgets('erro com nova tentativa', (tester) async {
      var falhar = true;
      final api = _Api(
        (m) => falhar
            ? http.Response('{"detail":"Servidor fora do ar"}', 503)
            : _ok(_resposta(m)),
      );
      await _abrir(tester, api);

      expect(find.text('Não foi possível carregar o ranking'), findsOneWidget);
      expect(find.text('Servidor fora do ar'), findsOneWidget);

      falhar = false;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('J01'), findsOneWidget);
      expect(api.pedidas, ['pontos', 'pontos']);
    });

    testWidgets('sem login, pede para entrar e não chama a API', (tester) async {
      final api = _Api((m) => _ok(_resposta(m)));
      await _abrir(tester, api, lerToken: () async => null);

      expect(find.text('Entre na sua conta para ver o ranking.'), findsOneWidget);
      expect(api.pedidas, isEmpty);
    });

    testWidgets('período sem ninguém: estado vazio, não lista em branco', (tester) async {
      final api = _Api((m) => _ok(_resposta(m, itens: [])));
      await _abrir(tester, api, aba: MetricaRanking.frequencia);

      expect(find.byKey(const ValueKey('ranking-vazio')), findsOneWidget);
      expect(find.text('Ninguém treinou nos últimos 7 dias.'), findsOneWidget);
      // Mesmo vazio, quem usa o app vê o convite, e o aviso de privacidade fica.
      expect(find.byKey(const ValueKey('convite')), findsOneWidget);
      expect(
        find.text('Só apelidos. Menores de idade ficam fora do ranking global por padrão.'),
        findsOneWidget,
      );
    });

    testWidgets('vazio para os outros, mas o menor vê a própria posição', (tester) async {
      final api = _Api(
        (m) => _ok(_resposta(m, itens: [], voce: _voce(1, 'Juninho', 300, oculto: true))),
      );
      await _abrir(tester, api);

      expect(find.byKey(const ValueKey('ranking-vazio')), findsOneWidget);
      expect(find.text(_aviso), findsOneWidget);
    });

    testWidgets('sucesso: pódio com o 1º ao centro e a lista do 4º em diante', (
      tester,
    ) async {
      final api = _Api((m) => _ok(_resposta(m)));
      await _abrir(tester, api);

      final x1 = tester.getCenter(find.byKey(const ValueKey('podio-1'))).dx;
      final x2 = tester.getCenter(find.byKey(const ValueKey('podio-2'))).dx;
      final x3 = tester.getCenter(find.byKey(const ValueKey('podio-3'))).dx;
      expect(x2 < x1 && x1 < x3, isTrue, reason: '2º, 1º, 3º');
      expect(
        tester.getSize(find.byKey(const ValueKey('podio-1'))).height,
        greaterThan(tester.getSize(find.byKey(const ValueKey('podio-2'))).height),
      );
      // Os três do pódio não se repetem na lista.
      for (final p in [1, 2, 3]) {
        expect(find.byKey(ValueKey('linha-$p')), findsNothing);
      }
      for (var p = 4; p <= 20; p++) {
        expect(find.byKey(ValueKey('linha-$p')), findsOneWidget, reason: '$p');
      }
    });

    testWidgets('pódio com menos de três não quebra', (tester) async {
      final api = _Api((m) => _ok(_resposta(m, itens: _lista(2))));
      await _abrir(tester, api);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('podio-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('podio-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('podio-3')), findsNothing);
    });
  });

  for (final grande in [false, true]) {
    testWidgets(
      'sem overflow em 360x640${grande ? ' · texto grande' : ''}, '
      'com lista cheia e a linha fixada',
      (tester) async {
        // Celular pequeno real: barra de status (24) e de gestos (16).
        tester.view.physicalSize = const Size(360, 640) * 3;
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
        addTearDown(tester.view.reset);
        AppSettings.textoGrande.value = grande;
        addTearDown(() => AppSettings.textoGrande.value = false);
        final api = _Api(
          (m) => _ok(
            _resposta(
              m,
              itens: [
                _item(1, 'ApelidoBemComprido01', 12345),
                ..._lista(20).skip(1),
              ],
              // O pior caso do rodapé: o aviso longo, de quem está oculto.
              voce: _voce(26, 'OutroApelidoComprido', 10, oculto: true, sessoes: 1),
            ),
          ),
        );
        for (final aba in MetricaRanking.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(fontFamily: 'Roboto'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    grande ? AppSettings.escalaGrande : 1.0,
                  ),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: RankingScreen(
                  key: ValueKey(aba),
                  aba: aba,
                  api: api.client,
                  lerToken: () async => 't',
                ),
                // A barra de abas do app (minHeight 80 em BottomNav).
                bottomNavigationBar: const SizedBox(height: 80),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: aba.name);
          // O rodapé fixo não pode engolir a lista: sobra área para rolar.
          final lista = tester.getRect(find.byType(ListView));
          expect(lista.height, greaterThan(250), reason: aba.name);
        }
      },
    );
  }

  testWidgets('resposta atrasada de outra aba não sobrescreve a atual', (tester) async {
    final pontos = Completer<http.Response>();
    final api = _Api(
      (m) => m == 'pontos'
          ? pontos.future
          : _ok(_resposta(m, itens: _lista(3, topo: 6, passo: 1))),
    );
    await _abrir(tester, api, assentar: false);
    await tester.pump();

    await _aba(tester, 'Frequência');
    await tester.pumpAndSettle();
    expect(find.text('6 dias'), findsOneWidget);

    pontos.complete(_ok(_resposta('pontos')));
    await tester.pumpAndSettle();
    expect(find.text('6 dias'), findsOneWidget);
    expect(find.text('3.000'), findsNothing);
  });
}
