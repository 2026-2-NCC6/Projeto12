// Capturas MANUAIS do Perfil, em 390×844 e 360×640, com respostas REAIS da
// API. Fica pulado na suíte normal; para gerar:
//
//   1. Backend no banco com dados (ex.: tobias_ranking) e salve, numa pasta,
//      GET /v1/auth/eu como eu.json e GET /v1/sessions?limit=100 como
//      sessoes.json (o usuário precisa ter menos de 100 sessões).
//   2. $env:PERFIL_JSON_DIR='C:\pasta\dos\json'
//      $env:CAPTURAS_DIR='C:\caminho\de\saida'
//      flutter test test/capturas/perfil_capturas_test.dart
@Tags(['capturas'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/auth_store.dart';
import 'package:smart_tennis_arena_mobile/router.dart';
import 'package:smart_tennis_arena_mobile/screens/perfil/config_perfil_screen.dart';
import 'package:smart_tennis_arena_mobile/screens/perfil/perfil_screen.dart';
import 'package:smart_tennis_arena_mobile/theme/app_theme.dart';
import 'package:smart_tennis_arena_mobile/transport/mock_transport.dart';

final _saida = Platform.environment['CAPTURAS_DIR'];
final _json = Platform.environment['PERFIL_JSON_DIR'];

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

ApiClient _api() => ApiClient(
  httpClient: MockClient((req) async {
    final arquivo = switch (req.url.path) {
      '/v1/auth/eu' => 'eu.json',
      '/v1/sessions' => 'sessoes.json',
      _ => null,
    };
    if (arquivo == null) return http.Response('{}', 200);
    return http.Response.bytes(
      File('$_json/$arquivo').readAsBytesSync(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

void main() {
  for (final (largura, altura, barras) in [(390.0, 844.0, false), (360.0, 640.0, true)]) {
    final sufixo = '${largura.toInt()}x${altura.toInt()}';
    testWidgets(
      'perfil, configurações e exclusão em $sufixo',
      (tester) async {
        tester.view.physicalSize = Size(largura, altura) * 2;
        tester.view.devicePixelRatio = 2;
        // 360×640: celular pequeno real, com barra de status e de gestos.
        if (barras) tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
        addTearDown(tester.view.reset);
        await tester.runAsync(_carregarFontes);

        final eu = UsuarioApi.fromJson(
          jsonDecode(File('$_json/eu.json').readAsStringSync()) as Map<String, dynamic>,
        );
        SharedPreferences.resetStatic();
        SharedPreferences.setMockInitialValues({});
        await AuthStore.salvarToken('t');
        await AuthStore.salvarUsuario(eu);

        final api = _api();
        final router = GoRouter(
          initialLocation: Routes.perfil,
          routes: [
            GoRoute(
              path: Routes.perfil,
              builder: (_, _) => TabShell(
                location: Routes.perfil,
                child: PerfilScreen(api: api, transport: MockTransport()),
              ),
            ),
            GoRoute(path: Routes.perfilConfig, builder: (_, _) => ConfigPerfilScreen(api: api)),
          ],
        );
        await tester.pumpWidget(
          RepaintBoundary(
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              locale: const Locale('pt', 'BR'),
              supportedLocales: const [Locale('pt', 'BR')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              routerConfig: router,
            ),
          ),
        );
        Future<void> assentar() async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await assentar();
        expect(find.byKey(const ValueKey('estatisticas')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturar(tester, 'perfil_$sufixo');

        router.push(Routes.perfilConfig);
        await assentar();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Apelido no ranking'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturar(tester, 'perfil_config_$sufixo');

        await tester.ensureVisible(find.text('Excluir minha conta'));
        await tester.tap(find.text('Excluir minha conta'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('campo-senha-exclusao')),
            matching: find.byType(TextField),
          ),
          'senha12345',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _capturar(tester, 'perfil_exclusao_$sufixo');

        await tester.pumpWidget(const SizedBox());
      },
      skip: _saida == null || _json == null,
    );
  }
}
