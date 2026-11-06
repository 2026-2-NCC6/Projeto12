// Capturas MANUAIS do Ranking, em 390×844, com respostas REAIS da API.
// Fica pulado na suíte normal; para gerar:
//
//   1. Backend no banco com dados (ex.: tobias_ranking, 43 usuários) e salve
//      GET /v1/ranking?metrica=<m> como <quem>-<m>.json, para quem = lider,
//      menor e fundo, numa pasta.
//   2. $env:RANKING_JSON_DIR='C:\pasta\dos\json'
//      $env:CAPTURAS_DIR='C:\caminho\de\saida'
//      flutter test test/capturas/ranking_capturas_test.dart
//
// O JSON é servido tal como a API devolveu, por um cliente HTTP falso (o
// `flutter test` não faz chamada de rede de verdade).
@Tags(['capturas'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/ranking.dart';
import 'package:smart_tennis_arena_mobile/router.dart';
import 'package:smart_tennis_arena_mobile/screens/ranking/ranking_screen.dart';
import 'package:smart_tennis_arena_mobile/theme/app_theme.dart';

final _saida = Platform.environment['CAPTURAS_DIR'];
final _json = Platform.environment['RANKING_JSON_DIR'];

Future<void> _carregarFontes() async {
  final roboto = FontLoader('Roboto');
  for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    roboto.addFont(
      Future.value(
        ByteData.sublistView(File('assets/fonts/Roboto-$peso.ttf').readAsBytesSync()),
      ),
    );
  }
  await roboto.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icones = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/'
            'materialicons-regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icones.load();
}

Future<void> _capturar(WidgetTester tester, String nome) async {
  final objeto = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final imagem = await objeto.toImage(pixelRatio: 2);
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    File('$_saida/$nome.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Serve `<quem>-<metrica>.json` como a API serviu.
ApiClient _api(String quem) => ApiClient(
  httpClient: MockClient((req) async {
    if (req.url.path == '/health') return http.Response('{}', 200);
    final m = req.url.queryParameters['metrica'];
    return http.Response.bytes(
      File('$_json/$quem-$m.json').readAsBytesSync(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

void main() {
  testWidgets(
    'ranking: três abas, a linha de quem usa e o menor',
    (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.runAsync(_carregarFontes);

      Future<void> abrir(String quem, MetricaRanking aba) async {
        await tester.pumpWidget(
          RepaintBoundary(
            child: MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              locale: const Locale('pt', 'BR'),
              supportedLocales: const [Locale('pt', 'BR')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              // A moldura de verdade das abas, com a BottomNav.
              home: TabShell(
                location: Routes.ranking,
                child: RankingScreen(
                  aba: aba,
                  api: _api(quem),
                  lerToken: () async => 't',
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(CircularProgressIndicator), findsNothing, reason: '$quem $aba');
      }

      // As três abas, vistas pelo LIDER (14º em pontos, 1º em frequência,
      // abaixo do mínimo na evolução).
      await abrir('lider', MetricaRanking.pontos);
      await _capturar(tester, 'ranking_pontos');
      await abrir('lider', MetricaRanking.frequencia);
      expect(find.byKey(const ValueKey('voce-no-podio')), findsOneWidget);
      await _capturar(tester, 'ranking_frequencia');
      await abrir('lider', MetricaRanking.evolucao);
      expect(find.byKey(const ValueKey('convite')), findsOneWidget);
      await _capturar(tester, 'ranking_evolucao');

      // Pontos rolado até a linha do LIDER, destacada no lugar dela.
      await abrir('lider', MetricaRanking.pontos);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('voce-na-lista')),
        200,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      await tester.pump();
      await _capturar(tester, 'ranking_pontos_sua_linha');

      // O menor (oculto): 20º contra a lista de adultos, o mesmo número do
      // 20º visível. Rodapé com o aviso de que não aparece.
      await abrir('menor', MetricaRanking.pontos);
      expect(find.byKey(const ValueKey('voce-fixado')), findsOneWidget);
      expect(find.text('Sua posição · você não aparece no ranking público'), findsOneWidget);
      await _capturar(tester, 'ranking_pontos_menor');

      // O adulto em 30º (não oculto): está no ranking, só abaixo dos 20.
      await abrir('fundo', MetricaRanking.pontos);
      expect(find.byKey(const ValueKey('voce-fixado')), findsOneWidget);
      expect(find.text('Sua posição'), findsOneWidget);
      expect(find.textContaining('não aparece'), findsNothing);
      await _capturar(tester, 'ranking_pontos_abaixo_do_corte');

      await tester.pumpWidget(const SizedBox());
    },
    skip: _saida == null || _json == null,
  );
}
