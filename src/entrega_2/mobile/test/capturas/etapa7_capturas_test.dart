// Capturas MANUAIS da etapa 7 (resumo com comparação e histórico), em 390
// pontos de largura. Fica pulado na suíte normal; para gerar:
//
//   $env:CAPTURAS_DIR='C:\caminho\de\saida'
//   flutter test test/capturas/etapa7_capturas_test.dart
//
// Três sessões seguidas no simulador (GravadorSessao + MockTransport), as
// duas primeiras sincronizadas com um servidor falso e a terceira pendente
// (rede fora). Depois, as telas reais dentro do app.
@Tags(['capturas'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/app.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/models.dart';
import 'package:smart_tennis_arena_mobile/data/resumo_sessao.dart';
import 'package:smart_tennis_arena_mobile/data/sincronizador.dart';
import 'package:smart_tennis_arena_mobile/router.dart';
import 'package:smart_tennis_arena_mobile/screens/sessao/resumo_screen.dart';
import 'package:smart_tennis_arena_mobile/state/gravador_sessao.dart';
import 'package:smart_tennis_arena_mobile/state/sessao_ativa.dart';
import 'package:smart_tennis_arena_mobile/transport/mock_transport.dart';

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

const _treino = Drill(
  id: 'reacao-rapida',
  titulo: 'Reação rápida',
  descricao: '',
  tipo: DrillType.catalogo,
  lances: 5,
  intervaloS: 3,
  nivel: Nivel.facil,
  versaoId: 7,
);

/// Uma sessão no simulador, com os ângulos [picos].
Future<String> _sessao(FilaSessoes fila, List<double> picos) async {
  final gravador = GravadorSessao(
    sessao: SessaoAtiva.iniciar(_treino, dificuldade: 0),
    fila: fila,
    transport: MockTransport(
      primeira: const Duration(milliseconds: 5),
      seguintes: const Duration(milliseconds: 5),
      picos: picos,
    ),
  );
  await gravador.iniciar();
  while (gravador.lancesGravados.value < _treino.lances) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await gravador.encerrar();
  // Sessões em instantes distintos, na ordem em que aconteceram.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return gravador.uuidSessao;
}

/// Servidor falso: aceita tudo, com a pontuação igual à do app.
Sincronizador _online(FilaSessoes fila) => Sincronizador(
  fila: () => fila,
  lerToken: () async => 't',
  api: ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/health') return http.Response('{}', 200);
      final enviadas = ((jsonDecode(req.body) as Map)['sessoes'] as List)
          .cast<Map<String, dynamic>>();
      return http.Response(
        jsonEncode({
          'sessoes': [
            for (final s in enviadas)
              {
                'uuid_sessao': s['uuid_sessao'],
                'situacao': 'inserida',
                'lances_recebidos': (s['lances'] as List).length,
                'lances_inseridos': (s['lances'] as List).length,
                'lances_duplicados': 0,
                'pontuacao_total': s['pontuacao_cliente'],
              },
          ],
        }),
        200,
      );
    }),
  ),
);

/// Sem rede: o envio falha e a sessão fica pendente.
Sincronizador _offline(FilaSessoes fila) => Sincronizador(
  fila: () => fila,
  lerToken: () async => 't',
  api: ApiClient(
    httpClient: MockClient((req) async => throw http.ClientException('sem rede')),
  ),
);

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

void main() {
  // As sessões rodam aqui, com relógio real (os timers do simulador não
  // andam dentro do relógio falso do testWidgets). O que foi gravado no
  // shared_preferences passa para o teste de tela.
  final uuids = <String>[];
  var gravado = <String, Object>{};

  setUpAll(() async {
    if (_saida == null) return;
    SharedPreferences.setMockInitialValues({});
    final fila = FilaSessoes();
    // 1ª e 2ª: sincronizam. 3ª: sem rede, fica pendente.
    uuids.add(await _sessao(fila, [31.0, 42.5, 47.0, 38.0, 44.5]));
    await _online(fila).sincronizar();
    uuids.add(await _sessao(fila, [45.0, 52.0, 49.5, 55.0, 47.5]));
    await _online(fila).sincronizar();
    uuids.add(await _sessao(fila, [51.0, 58.5, 48.0, 61.0, 53.5]));
    final s = _offline(fila);
    await s.sincronizar();
    s.cancelarAgendamento();
    final prefs = await SharedPreferences.getInstance();
    gravado = {FilaSessoes.chave: prefs.getString(FilaSessoes.chave)!};
  });

  testWidgets(
    'três sessões no simulador: comparação e histórico',
    (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues(gravado);
      FilaSessoes.reiniciarParaTestes();
      final fila = FilaSessoes.doApp;
      await tester.runAsync(_carregarFontes);

      // Conferências da etapa (o que a captura deve mostrar).
      final historico = await fila.historico();
      expect([for (final s in historico) s.uuidSessao], uuids.reversed);
      expect([for (final s in historico) s.sincronizada], [false, true, true]);
      final variacoes = [
        for (final u in uuids)
          variacaoSobreAnterior(
            historico.firstWhere((s) => s.uuidSessao == u),
            historico,
          ),
      ];
      expect(variacoes[0], isNull);
      expect(variacoes[1], isNotNull);
      expect(variacoes[2], isNotNull);
      // Etapa 7b: os números da 3ª fecham (faixas pelo ângulo).
      final terceira = ResumoSessao.de(historico.first);
      expect(
        (terceira.lances, terceira.acertos, terceira.fracos, terceira.medios, terceira.kos, terceira.erros),
        (5, 5, 0, 3, 2, 0),
      );
      // ignore: avoid_print
      print('uuids: $uuids');
      // ignore: avoid_print
      print('pontuações: ${[for (final s in historico.reversed) s.pontuacaoExibida]}');
      // ignore: avoid_print
      print('variações: $variacoes');

      Future<void> abrir(String rota) async {
        await tester.pumpWidget(
          RepaintBoundary(
            child: SmartTennisArenaApp(key: UniqueKey(), initialLocation: rota),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      for (var i = 0; i < 3; i++) {
        await abrir(
          '${Routes.sessaoResumo}?sessao=${uuids[i]}&treino=Reação rápida',
        );
        final linha = find.textContaining('sessão anterior');
        expect(linha, i == 0 ? findsNothing : findsOneWidget, reason: 'sessão ${i + 1}');
        if (i > 0) expect(find.text(textoVariacao(variacoes[i]!)), findsOneWidget);
        await _capturar(tester, 'resumo_sessao_${i + 1}');
      }

      await abrir(Routes.historico);
      expect(find.text('Pendente'), findsOneWidget);
      expect(find.text('Sincronizado'), findsNWidgets(2));
      await _capturar(tester, 'historico');
      await tester.pumpWidget(const SizedBox());
    },
    skip: _saida == null,
  );
}
