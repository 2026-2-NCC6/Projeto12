import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/dashboard.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/screens/historico/dashboard_screen.dart';
import 'package:smart_tennis_arena_mobile/widgets/controls.dart';

var _n = 0;

/// Uma sessão da API iniciada em [inicio] (UTC).
Map<String, dynamic> _json(
  DateTime inicio, {
  int pontos = 100,
  int acertos = 8,
  int erros = 2,
  int kos = 1,
  int sequencia = 4,
}) {
  _n++;
  return {
    'uuid_sessao': '00000000-0000-4000-8000-${_n.toString().padLeft(12, '0')}',
    'treino_titulo': 'Reação rápida',
    'treino_versao': 1,
    'iniciada_em': inicio.toUtc().toIso8601String(),
    'encerrada_em': null,
    'pontuacao_total': pontos,
    'versao_pontuacao': 1,
    'acertos': acertos,
    'erros': erros,
    'kos': kos,
    'melhor_sequencia': sequencia,
    'precisao': acertos + erros == 0
        ? null
        : (acertos * 1000 / (acertos + erros)).round() / 10,
  };
}

SessaoApi _s(DateTime inicio, {int pontos = 100, int acertos = 8, int erros = 2, int kos = 1, int sequencia = 4}) =>
    SessaoApi.fromJson(
      _json(inicio, pontos: pontos, acertos: acertos, erros: erros, kos: kos, sequencia: sequencia),
    );

/// Servidor falso de GET /v1/sessions: filtra por `de`/`ate` (inclusivos)
/// e pagina, como a API. [falhar] simula a rede fora.
class _Api {
  _Api(this.sessoes);

  final List<Map<String, dynamic>> sessoes;
  var falhar = false;
  final caminhos = <String>[];

  ApiClient get cliente => ApiClient(
    httpClient: MockClient((req) async {
      caminhos.add(req.url.path);
      if (req.url.path == '/health') return http.Response('{}', 200);
      if (falhar) throw http.ClientException('sem rede');
      final q = req.url.queryParameters;
      final de = q['de'] == null ? null : DateTime.parse(q['de']!);
      final ate = q['ate'] == null ? null : DateTime.parse(q['ate']!);
      final filtradas = [
        for (final s in sessoes)
          if ((de == null || !DateTime.parse(s['iniciada_em'] as String).isBefore(de)) &&
              (ate == null || !DateTime.parse(s['iniciada_em'] as String).isAfter(ate)))
            s,
      ]..sort((a, b) => (b['iniciada_em'] as String).compareTo(a['iniciada_em'] as String));
      final limit = int.parse(q['limit']!), offset = int.parse(q['offset']!);
      return http.Response(
        jsonEncode({
          'items': filtradas.skip(offset).take(limit).toList(),
          'total': filtradas.length,
          'limit': limit,
          'offset': offset,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

void main() {
  group('agregados', () {
    test('precisão ponderada por lances, não média das médias', () {
      final a = agregar([
        _s(DateTime.utc(2026, 11, 1), acertos: 3, erros: 0, kos: 0), // 100%
        _s(DateTime.utc(2026, 11, 2), acertos: 15, erros: 15, kos: 0), // 50%
      ]);
      // Média das médias daria 75%. Ponderada: 18 de 33 lances.
      expect(a.precisao, closeTo(18 / 33, 1e-12));
      expect(a.precisao, isNot(closeTo(0.75, 0.01)));
    });

    test('distribuição: acertos − kos no 1º segmento, e soma o total', () {
      final a = agregar([
        _s(DateTime.utc(2026, 11, 1), acertos: 12, erros: 3, kos: 2),
        _s(DateTime.utc(2026, 11, 2), acertos: 8, erros: 5, kos: 3),
      ]);
      final d = a.distribuicao;
      expect((d.acertosSemKo, d.kos, d.erros), (15, 5, 8));
      expect(d.acertosSemKo + d.kos + d.erros, 20 + 8);
      expect(d.total, 28);
      final (p1, p2, p3) = d.porcentagens!;
      expect(p1 + p2 + p3, 100);
    });

    test('porcentagens somam 100 mesmo quando o arredondamento não fecharia', () {
      // 1/3 de cada: 33,3 + 33,3 + 33,3 arredondaria para 99.
      const d = Distribuicao(acertosSemKo: 1, kos: 1, erros: 1);
      final (a, b, c) = d.porcentagens!;
      expect(a + b + c, 100);
    });

    test('pontuação, contagem e melhor sequência do período', () {
      final a = agregar([
        _s(DateTime.utc(2026, 11, 2), pontos: 300, sequencia: 7),
        _s(DateTime.utc(2026, 11, 1), pontos: 200, sequencia: 9),
      ]);
      expect(a.pontuacaoTotal, 500);
      expect(a.sessoes, hasLength(2));
      expect(a.melhorSequencia, 9);
      // Cronológica, para o gráfico.
      expect(a.sessoes.first.iniciadaEm, DateTime.utc(2026, 11, 1));
    });

    test('variação: % na pontuação, pontos percentuais na precisão', () {
      final antes = agregar([_s(DateTime.utc(2026, 10, 1), pontos: 200, acertos: 84, erros: 16)]);
      final agora = agregar([_s(DateTime.utc(2026, 11, 1), pontos: 236, acertos: 90, erros: 10)]);
      expect(variacaoPontuacao(agora, antes), 18);
      expect(variacaoPrecisaoPts(agora, antes), 6); // 84% → 90%, não 7%
    });

    test('sem período anterior ("Tudo") ou com base zero: sem variação', () {
      final agora = agregar([_s(DateTime.utc(2026, 11, 1))]);
      expect(variacaoPontuacao(agora, null), isNull);
      expect(variacaoPrecisaoPts(agora, null), isNull);
      expect(variacaoPontuacao(agora, agregar([])), isNull);
    });
  });

  group('janelas', () {
    test('7 dias: hoje e os 6 anteriores; a anterior termina 1 ms antes', () {
      final agora = DateTime(2026, 11, 5, 15, 30);
      final (atual, anterior) = janelas(PeriodoDashboard.seteDias, agora)!;
      expect(atual.de, DateTime(2026, 10, 30));
      expect(atual.ate, agora);
      expect(anterior.de, DateTime(2026, 10, 23));
      expect(anterior.ate, DateTime(2026, 10, 30).subtract(const Duration(milliseconds: 1)));
    });

    test('"Tudo" não tem janela nem período anterior', () {
      expect(janelas(PeriodoDashboard.tudo, DateTime(2026, 11, 5)), isNull);
    });
  });

  group('frequência semanal', () {
    // São Paulo, fixo em −03:00 (sem depender do fuso da máquina de testes).
    DateTime saoPaulo(DateTime utc) => utc.subtract(const Duration(hours: 3));

    test('sessão às 22h em São Paulo cai no dia local, não no dia UTC', () {
      // 22h de 04/11 em São Paulo = 01h de 05/11 em UTC.
      final noturna = _s(DateTime.utc(2026, 11, 5, 1));
      final agora = DateTime(2026, 11, 5, 9); // quinta, 05/11

      final dias = frequenciaSemanal([noturna], agora, paraLocal: saoPaulo);

      expect([for (final (d, _) in dias) d.day], [30, 31, 1, 2, 3, 4, 5]);
      final ativo = {for (final (d, a) in dias) d.day: a};
      expect(ativo[4], isTrue, reason: 'treinou na quarta à noite');
      expect(ativo[5], isFalse, reason: 'agrupar pelo UTC cru cairia aqui');
    });

    test('várias sessões no mesmo dia contam um dia só', () {
      final agora = DateTime(2026, 11, 5, 23);
      final dias = frequenciaSemanal(
        [
          _s(DateTime.utc(2026, 11, 5, 12)),
          _s(DateTime.utc(2026, 11, 5, 18)),
          _s(DateTime.utc(2026, 11, 3, 12)),
          _s(DateTime.utc(2026, 10, 20, 12)), // fora dos 7 dias
        ],
        agora,
        paraLocal: saoPaulo,
      );
      expect(dias.where((d) => d.$2), hasLength(2));
    });
  });

  group('tela', () {
    final agora = DateTime(2026, 11, 5, 15);

    setUp(() {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> abrir(WidgetTester tester, _Api api, {FilaSessoes? fila, String? token = 't'}) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              api: api.cliente,
              fila: fila ?? FilaSessoes(),
              lerToken: () async => token,
              agora: () => agora,
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    Future<void> chip(WidgetTester tester, String rotulo) async {
      await tester.tap(find.text(rotulo));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    _Api comSessoes() => _Api([
      // Período atual (30 dias) e o anterior, para haver variação.
      _json(agora.subtract(const Duration(days: 2)), pontos: 300),
      _json(agora.subtract(const Duration(days: 10)), pontos: 200),
      _json(agora.subtract(const Duration(days: 40)), pontos: 250),
    ]);

    testWidgets('acorda a API antes de consultar', (tester) async {
      final api = comSessoes();
      await abrir(tester, api);
      expect(api.caminhos.first, '/health');
      expect(api.caminhos, contains('/v1/sessions'));
    });

    testWidgets('30 dias: soma, contagem e selo de variação', (tester) async {
      await abrir(tester, comSessoes());
      expect(find.text('Pontuação total · 2 sessões'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      // 500 contra 250 no período anterior: +100%.
      expect(find.text('+100%'), findsOneWidget);
      expect(find.byType(AppBadge), findsOneWidget);
    });

    testWidgets('"Tudo" não mostra selo de variação', (tester) async {
      await abrir(tester, comSessoes());
      await chip(tester, 'Tudo');
      expect(find.text('Pontuação total · 3 sessões'), findsOneWidget);
      // Nem o selo da pontuação, nem a variação da precisão.
      expect(find.byType(AppBadge), findsNothing);
      expect(find.textContaining(' pts vs.'), findsNothing);
    });

    testWidgets('período sem sessões: estado vazio, não zeros', (tester) async {
      await abrir(tester, _Api([_json(agora.subtract(const Duration(days: 20)))]));
      await chip(tester, '7 dias');
      expect(find.text('Nenhuma sessão enviada nos últimos 7 dias.'), findsOneWidget);
      expect(find.textContaining('Pontuação total'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('quem nunca enviou sessão: vazio também em "Tudo"', (tester) async {
      await abrir(tester, _Api([]));
      await chip(tester, 'Tudo');
      expect(find.text('Você ainda não tem sessões enviadas.'), findsOneWidget);
    });

    testWidgets('sem rede: erro com nova tentativa, sem cair para o local', (tester) async {
      final api = comSessoes()..falhar = true;
      await abrir(tester, api);
      expect(find.text('Não foi possível carregar o Dashboard'), findsOneWidget);
      expect(find.textContaining('Pontuação total'), findsNothing);

      api.falhar = false;
      await tester.tap(find.text('Tentar de novo'));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(find.text('Pontuação total · 2 sessões'), findsOneWidget);
    });

    testWidgets('frequência: dias com três letras, do mais antigo a hoje', (tester) async {
      await abrir(tester, comSessoes());
      // 05/11/2026 é quinta: de sexta (30/10) a quinta.
      final rotulos = [
        for (final d in ['Sex', 'Sáb', 'Dom', 'Seg', 'Ter', 'Qua', 'Qui'])
          tester.getTopLeft(find.text(d)).dx,
      ];
      expect(rotulos, orderedEquals([...rotulos]..sort()));
    });

    testWidgets('hoje (o último dia) tem o anel, treinado ou não', (tester) async {
      for (final treinouHoje in [true, false]) {
        await abrir(
          tester,
          _Api([
            _json(agora.subtract(Duration(days: treinouHoje ? 0 : 2))),
          ]),
        );
        final anel = find.byKey(const ValueKey('frequencia-hoje'));
        expect(anel, findsOneWidget, reason: 'treinou hoje: $treinouHoje');
        // É o círculo mais à direita, sobre o rótulo de hoje (quinta).
        expect(
          tester.getCenter(anel).dx,
          closeTo(tester.getCenter(find.text('Qui')).dx, 1),
        );
        // O rótulo de hoje continua normal, como os outros.
        expect(
          tester.widget<Text>(find.text('Qui')).style,
          tester.widget<Text>(find.text('Qua')).style,
        );
      }
    });

    testWidgets('pendentes na fila: avisa que não estão incluídas', (tester) async {
      final fila = FilaSessoes();
      for (final u in ['p1', 'p2']) {
        await fila.abrir(
          SessaoLocal(
            uuidSessao: u,
            treinoVersaoId: 1,
            dificuldade: 0,
            iniciadaEm: '2026-11-05T10:00:00.000Z',
          ),
        );
      }
      await abrir(tester, comSessoes(), fila: fila);
      expect(find.text('2 sessões ainda não enviadas não estão incluídas'), findsOneWidget);
    });

    testWidgets('distribuição na tela: KO destacado de dentro dos acertos', (tester) async {
      await abrir(tester, _Api([
        _json(agora.subtract(const Duration(days: 1)), acertos: 39, erros: 8, kos: 3),
      ]));
      expect(find.text('47 lances'), findsOneWidget);
      // O rótulo resolve sozinho; sem a frase que repetia a legenda.
      expect(find.text('Acertos sem KO'), findsOneWidget);
      expect(find.textContaining('destacado de dentro dos acertos'), findsNothing);
    });
  });
}
