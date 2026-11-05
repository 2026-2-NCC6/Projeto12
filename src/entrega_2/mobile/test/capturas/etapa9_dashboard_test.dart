// Captura MANUAL do Dashboard (etapa 9), em 390 pontos de largura. Fica
// pulada na suíte normal; para gerar:
//
//   $env:CAPTURAS_DIR='C:\caminho\de\saida'
//   flutter test test/capturas/etapa9_dashboard_test.dart
//
// DADOS DE TESTE: produção tem só quatro sessões, pouco para os blocos
// ficarem legíveis. As sessões abaixo são SINTÉTICAS, servidas por uma API
// falsa (MockClient) no formato exato de GET /v1/sessions. O "agora" é
// fixo: 05/11/2026 19:00 no fuso do aparelho.
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
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/router.dart';
import 'package:smart_tennis_arena_mobile/screens/historico/dashboard_screen.dart';
import 'package:smart_tennis_arena_mobile/theme/app_theme.dart';

final _saida = Platform.environment['CAPTURAS_DIR'];
final _agora = DateTime(2026, 11, 5, 19);

/// (dias atrás, hora local, pontos, acertos, erros, kos, melhor sequência)
const _sessoes = [
  // Últimos 7 dias: 5 dias treinados (hoje, 1, 2, 4 e 5 dias atrás),
  // com uma sessão às 22h, que em UTC já é o dia seguinte.
  (0, 8, 1980, 17, 3, 2, 9),
  (1, 22, 1745, 16, 4, 1, 7),
  (2, 19, 1610, 15, 5, 1, 6),
  (2, 7, 1320, 13, 7, 0, 5),
  (4, 18, 1890, 17, 3, 2, 8),
  (5, 20, 1505, 15, 5, 1, 6),
  // Resto dos 30 dias.
  (8, 19, 1450, 14, 6, 1, 6),
  (11, 18, 1380, 14, 6, 1, 5),
  (13, 20, 1210, 13, 7, 0, 4),
  (16, 19, 1530, 15, 5, 1, 6),
  (19, 9, 1295, 13, 7, 1, 5),
  (22, 21, 1170, 12, 8, 0, 4),
  (25, 19, 1340, 14, 6, 0, 5),
  (28, 18, 1100, 12, 8, 0, 4),
  // Os 30 dias anteriores (para a variação): mais fracos.
  (32, 19, 1050, 12, 8, 0, 4),
  (35, 18, 980, 11, 9, 0, 3),
  (38, 20, 1120, 12, 8, 1, 4),
  (41, 19, 900, 10, 10, 0, 3),
  (44, 18, 1010, 11, 9, 0, 4),
  (47, 19, 1080, 12, 8, 0, 4),
  (50, 20, 950, 11, 9, 0, 3),
  (54, 18, 1030, 11, 9, 1, 4),
  (58, 19, 990, 11, 9, 0, 3),
];

List<Map<String, dynamic>> _json() => [
  for (final (i, (dias, hora, pontos, acertos, erros, kos, seq)) in _sessoes.indexed)
    {
      'uuid_sessao': '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
      'treino_titulo': 'Reação rápida',
      'treino_versao': 1,
      'iniciada_em': DateTime(_agora.year, _agora.month, _agora.day - dias, hora)
          .toUtc()
          .toIso8601String(),
      'encerrada_em': null,
      'pontuacao_total': pontos,
      'versao_pontuacao': 1,
      'acertos': acertos,
      'erros': erros,
      'kos': kos,
      'melhor_sequencia': seq,
      'precisao': (acertos * 1000 / (acertos + erros)).round() / 10,
    },
];

ApiClient _api() {
  final todas = _json();
  return ApiClient(
    httpClient: MockClient((req) async {
      if (req.url.path == '/health') return http.Response('{}', 200);
      final q = req.url.queryParameters;
      final de = q['de'] == null ? null : DateTime.parse(q['de']!);
      final ate = q['ate'] == null ? null : DateTime.parse(q['ate']!);
      final f = [
        for (final s in todas)
          if ((de == null || !DateTime.parse(s['iniciada_em'] as String).isBefore(de)) &&
              (ate == null || !DateTime.parse(s['iniciada_em'] as String).isAfter(ate)))
            s,
      ];
      final limit = int.parse(q['limit']!), offset = int.parse(q['offset']!);
      return http.Response(
        jsonEncode({
          'items': f.skip(offset).take(limit).toList(),
          'total': f.length,
          'limit': limit,
          'offset': offset,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

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
  final raiz = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icones = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('$raiz/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
              .readAsBytesSync(),
        ),
      ),
    );
  await icones.load();
}

void main() {
  testWidgets(
    'Dashboard com dados de teste',
    (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 1060 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(_carregarFontes);

      // Duas sessões que ainda não subiram, para a linha de aviso aparecer.
      final fila = FilaSessoes();
      for (final u in ['pendente-1', 'pendente-2']) {
        await fila.abrir(
          SessaoLocal(
            uuidSessao: u,
            treinoVersaoId: 1,
            dificuldade: 0,
            iniciadaEm: _agora.toUtc().toIso8601String(),
          ),
        );
      }

      await tester.pumpWidget(
        RepaintBoundary(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: TabShell(
              location: Routes.historicoDashboard,
              child: DashboardScreen(
                api: _api(),
                fila: fila,
                lerToken: () async => 'token-de-teste',
                agora: () => _agora,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Pontuação total · 14 sessões'), findsOneWidget);
      expect(find.text('2 sessões ainda não enviadas não estão incluídas'), findsOneWidget);
      expect(find.text('5 de 7 dias'), findsOneWidget);

      final objeto = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final imagem = await objeto.toImage(pixelRatio: 2);
        final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
        // No Windows, um PNG aberto em outro programa não pode ser
        // sobrescrito (erro 1224): tenta por uns segundos e, se seguir
        // preso, grava ao lado com outro nome, dizendo qual.
        final dados = bytes!.buffer.asUint8List();
        var destino = File('$_saida/dashboard.png');
        for (var tentativa = 1; ; tentativa++) {
          try {
            destino.writeAsBytesSync(dados);
            break;
          } on FileSystemException {
            if (tentativa == 10) {
              destino = File(
                '$_saida/dashboard-${DateTime.now().millisecondsSinceEpoch}.png',
              );
              destino.writeAsBytesSync(dados);
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        // ignore: avoid_print
        print('captura: ${destino.path}');
      });
      await tester.pumpWidget(const SizedBox());
    },
    skip: _saida == null,
  );
}
