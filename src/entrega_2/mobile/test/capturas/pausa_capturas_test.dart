// Capturas MANUAIS da tela em andamento (RF06: pausa), em 390×844, o mesmo
// tamanho das outras capturas. Fica pulado na suíte normal; para gerar:
//
//   $env:CAPTURAS_DIR='C:\caminho\de\saida'
//   flutter test test/capturas/pausa_capturas_test.dart
//
// Duas imagens: a sessão rodando e a mesma tela depois de um PAUSAR que o
// Tobias não confirmou em 1,5 s.
@Tags(['capturas'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/models.dart';
import 'package:smart_tennis_arena_mobile/screens/sessao/em_andamento_screen.dart';
import 'package:smart_tennis_arena_mobile/state/sessao_ativa.dart';
import 'package:smart_tennis_arena_mobile/theme/app_theme.dart';
import 'package:smart_tennis_arena_mobile/transport/device_transport.dart';

final _saida = Platform.environment['CAPTURAS_DIR'];

Future<void> _carregarFontes() async {
  final roboto = FontLoader('Roboto');
  for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    roboto.addFont(
      Future.value(
        ByteData.sublistView(
          File('assets/fonts/Roboto-$peso.ttf').readAsBytesSync(),
        ),
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

/// Tobias que recebe os comandos e nunca confirma.
class _TobiasMudo implements DeviceTransport {
  @override
  Stream<ImpactEvent> get events => const Stream.empty();
  @override
  Stream<StatusTobias> get estados => const Stream.empty();
  @override
  Future<void> send(
    DeviceCommand cmd, {
    int lances = 15,
    int intervaloMs = 3000,
    double calibracao = 0.0,
  }) async {}
  @override
  Future<DeviceStatus> status() async =>
      const DeviceStatus(nome: 'TOBIAS', conectado: true, bateria: 90);
  @override
  Future<void> disconnect() async {}
}

const _treino = Drill(
  id: 'reacao-rapida',
  titulo: 'Reação rápida',
  descricao: '',
  tipo: DrillType.catalogo,
  lances: 15,
  intervaloS: 3,
  nivel: Nivel.facil,
  versaoId: 7,
);

void main() {
  testWidgets(
    'em andamento: rodando e com a falha de pausa',
    (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(_carregarFontes);

      await tester.pumpWidget(
        RepaintBoundary(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            locale: const Locale('pt', 'BR'),
            supportedLocales: const [Locale('pt', 'BR')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: EmAndamentoScreen(
              sessao: SessaoAtiva.iniciar(_treino, dificuldade: 0),
              fila: FilaSessoes(),
              transport: _TobiasMudo(),
            ),
          ),
        ),
      );
      await tester.pump();
      // 12 s de sessão, para o cronômetro não aparecer zerado.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await _capturar(tester, 'em_andamento');

      await tester.tap(find.text('Pausar'));
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.textContaining('comando de pausa não foi'), findsOneWidget);
      await _capturar(tester, 'em_andamento_falha_pausa');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    skip: _saida == null,
  );
}
