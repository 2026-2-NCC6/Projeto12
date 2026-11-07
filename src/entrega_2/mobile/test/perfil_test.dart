import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/auth_store.dart';
import 'package:smart_tennis_arena_mobile/data/dashboard.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/perfil.dart';
import 'package:smart_tennis_arena_mobile/router.dart';
import 'package:smart_tennis_arena_mobile/screens/connect/pareamento_screen.dart';
import 'package:smart_tennis_arena_mobile/screens/perfil/config_perfil_screen.dart';
import 'package:smart_tennis_arena_mobile/screens/perfil/conta_excluida_screen.dart';
import 'package:smart_tennis_arena_mobile/screens/perfil/perfil_screen.dart';
import 'package:smart_tennis_arena_mobile/transport/mock_transport.dart';

/// São Paulo sem horário de verão (UTC−3), para os testes não dependerem do
/// fuso da máquina que roda.
DateTime _sp(DateTime d) => d.toUtc().subtract(const Duration(hours: 3));

/// Instante UTC de uma hora LOCAL de São Paulo.
DateTime _emSp(int ano, int mes, int dia, int hora) =>
    DateTime.utc(ano, mes, dia, hora).add(const Duration(hours: 3));

UsuarioApi _usuario({DateTime? calibradoEm, double calibracao = 0, String apelido = 'Vick'}) =>
    UsuarioApi(
      id: 7,
      email: 'vitoria@tobias.dev',
      papel: 'jogador',
      nome: 'Vitória Leticia',
      apelido: apelido,
      perfil: 'casual',
      calibracao: calibracao,
      calibradoEm: calibradoEm,
    );

SessaoApi _sessao(DateTime iniciadaEm, {int? pontos = 100, int melhorSequencia = 1}) =>
    SessaoApi(
      uuidSessao: 'u-${iniciadaEm.millisecondsSinceEpoch}',
      treinoTitulo: 'Treino',
      treinoVersao: 1,
      iniciadaEm: iniciadaEm.toUtc(),
      encerradaEm: null,
      pontuacaoTotal: pontos,
      acertos: 3,
      erros: 0,
      kos: 0,
      melhorSequencia: melhorSequencia,
      precisao: 100,
    );

Map<String, dynamic> _sessaoJson(DateTime iniciadaEm, {int? pontos, int melhorSequencia = 1}) => {
  'uuid_sessao': 'u-${iniciadaEm.millisecondsSinceEpoch}',
  'treino_titulo': 'Treino',
  'treino_versao': 1,
  'iniciada_em': iniciadaEm.toUtc().toIso8601String(),
  'encerrada_em': null,
  'pontuacao_total': pontos,
  'versao_pontuacao': 1,
  'acertos': 3,
  'erros': 0,
  'kos': 0,
  'melhor_sequencia': melhorSequencia,
  'precisao': 100.0,
};

http.Response _json(Object corpo, [int status = 200]) => http.Response(
  jsonEncode(corpo),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
  });

  // ------------------------------------------------------------- Calibração

  group('quem precisa calibrar', () {
    test('calibrado_em nulo precisa; preenchido, não', () {
      expect(_usuario().precisaCalibrar, isTrue);
      expect(_usuario(calibradoEm: DateTime.utc(2026, 11, 1)).precisaCalibrar, isFalse);
    });

    test('calibração 0 com calibrado_em preenchido NÃO precisa', () {
      // Mediana de 38° ou menos dá 0: resultado legítimo, igual ao valor de
      // quem nunca calibrou. Só calibrado_em separa os dois.
      final calibrouComZero = _usuario(calibracao: 0, calibradoEm: DateTime.utc(2026, 11, 1));
      final nunca = _usuario(calibracao: 0);
      expect(calibrouComZero.calibracao, nunca.calibracao);
      expect(calibrouComZero.precisaCalibrar, isFalse);
      expect(nunca.precisaCalibrar, isTrue);
    });

    test('o /eu traz calibrado_em, e o guardado no aparelho também', () async {
      final api = UsuarioApi.fromJson({
        'id': 7,
        'email': 'v@t.dev',
        'nome': 'V',
        'apelido': 'Vick',
        'perfil': 'casual',
        'papel': 'jogador',
        'calibracao': 0.0,
        'calibrado_em': '2026-11-19T13:00:00Z',
      });
      expect(api.calibradoEm, DateTime.utc(2026, 11, 19, 13));
      await AuthStore.salvarUsuario(api);
      final lido = (await AuthStore.lerUsuario())!;
      expect(lido.calibradoEm, api.calibradoEm);
      expect(lido.precisaCalibrar, isFalse);
      expect((lido.apelido, lido.nome, lido.perfil), ('Vick', 'V', 'casual'));
    });

    Future<void> conectado(WidgetTester tester, UsuarioApi? u) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PareamentoScreen(
            estadoInicial: EstadoPareamento.conectado,
            lerUsuario: () async => u,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('pareamento: nunca calibrou leva à calibração', (tester) async {
      await conectado(tester, _usuario());
      expect(find.text('Continuar para a calibração'), findsOneWidget);
      expect(find.text('Começar a treinar'), findsNothing);
    });

    testWidgets('pareamento: já calibrou (mesmo com 0) vai direto treinar', (tester) async {
      await conectado(tester, _usuario(calibracao: 0, calibradoEm: DateTime.utc(2026, 11, 1)));
      expect(find.text('Começar a treinar'), findsOneWidget);
      expect(find.text('Continuar para a calibração'), findsNothing);
      expect(find.textContaining('Para recalibrar, use o Perfil'), findsOneWidget);
    });

    testWidgets('pareamento: sem usuário guardado calibra, como antes', (tester) async {
      await conectado(tester, null);
      expect(find.text('Continuar para a calibração'), findsOneWidget);
    });
  });

  // ------------------------------------------------------- Dias seguidos

  group('dias seguidos treinando', () {
    // Quinta, 05/11/2026, 12:00 em São Paulo.
    final agora = _emSp(2026, 11, 5, 12);
    int dias(List<DateTime> inicios) => diasSeguidos(inicios, agora, paraLocal: _sp);

    test('dias consecutivos até hoje, contando cada dia uma vez', () {
      expect(
        dias([
          _emSp(2026, 11, 5, 8),
          _emSp(2026, 11, 5, 19), // segunda do mesmo dia
          _emSp(2026, 11, 4, 9),
          _emSp(2026, 11, 3, 9),
          _emSp(2026, 11, 1, 9), // depois de um buraco: não conta
        ]),
        3,
      );
    });

    test('viva com treino ontem e nada hoje', () {
      expect(dias([_emSp(2026, 11, 4, 9), _emSp(2026, 11, 3, 9)]), 2);
    });

    test('morta com três dias de intervalo', () {
      expect(dias([_emSp(2026, 11, 2, 9), _emSp(2026, 11, 1, 9)]), 0);
      expect(dias([]), 0);
    });

    test('sessão às 22h conta no dia local, não no de UTC', () {
      // 04/11 às 22h em SP = 05/11 01:00 em UTC.
      final as22h = _emSp(2026, 11, 4, 22);
      expect(as22h.day, 5, reason: 'em UTC já é o dia seguinte');
      final sessoes = [as22h, _emSp(2026, 11, 3, 10)];
      // No fuso local: 04 (ontem) e 03 → 2 dias, viva.
      expect(dias(sessoes), 2);
      // Agrupando em UTC daria 05 e 03: 1 dia só. É o erro a evitar.
      expect(diasSeguidos(sessoes, agora, paraLocal: (d) => d.toUtc()), 1);
    });

    test('atravessa a virada do mês', () {
      final primeiro = _emSp(2026, 12, 1, 12);
      expect(
        diasSeguidos(
          [_emSp(2026, 12, 1, 8), _emSp(2026, 11, 30, 8), _emSp(2026, 11, 29, 8)],
          primeiro,
          paraLocal: _sp,
        ),
        3,
      );
    });

    test('sessões, recorde e sequência: o total vem do envelope', () {
      final e = estatisticasPerfil(
        [
          _sessao(_emSp(2026, 11, 5, 9), pontos: 300),
          _sessao(_emSp(2026, 11, 4, 9), pontos: null), // não pontuada
          _sessao(_emSp(2026, 11, 4, 20), pontos: 950),
        ],
        57,
        agora,
        paraLocal: _sp,
      );
      expect(e.sessoes, 57);
      expect(e.recorde, 950);
      expect(e.diasSeguidos, 2);
    });
  });

  // --------------------------------------------------------- Texto do TOBIAS

  group('linha da calibração no cartão', () {
    final agora = _emSp(2026, 11, 20, 12);

    test('data e dificuldade em graus', () {
      expect(
        textoCalibracao(_emSp(2026, 11, 19, 10), 12.5, agora: agora, paraLocal: _sp),
        'Calibrado em 19 nov · dificuldade +12,5°',
      );
    });

    test('dificuldade 0: só a data, sem "+0,0°"', () {
      expect(
        textoCalibracao(_emSp(2026, 11, 19, 10), 0, agora: agora, paraLocal: _sp),
        'Calibrado em 19 nov',
      );
    });

    test('outro ano leva o ano; nunca calibrou é nulo', () {
      expect(
        textoCalibracao(_emSp(2025, 3, 2, 10), 3, agora: agora, paraLocal: _sp),
        'Calibrado em 2 mar 2025 · dificuldade +3,0°',
      );
      expect(textoCalibracao(null, 5, agora: agora), isNull);
    });
  });

  // ------------------------------------------------------------ Tela Perfil

  group('tela de Perfil', () {
    Future<void> abrir(
      WidgetTester tester, {
      required ApiClient api,
      UsuarioApi? usuario,
      DateTime? agora,
    }) async {
      tester.view.physicalSize = const Size(390, 1400) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PerfilScreen(
              api: api,
              lerToken: () async => 't',
              lerUsuario: () async => usuario ?? _usuario(),
              transport: MockTransport(),
              agora: () => agora ?? DateTime.now(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ApiClient apiCom(List<Map<String, dynamic>> sessoes, {int? total, UsuarioApi? eu}) =>
        ApiClient(
          httpClient: MockClient((req) async {
            if (req.url.path == '/health') return http.Response('{}', 200);
            if (req.url.path == '/v1/auth/eu') return _json((eu ?? _usuario()).toJson());
            final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
            return _json({
              'items': offset == 0 ? sessoes : [],
              'total': total ?? sessoes.length,
              'limit': 100,
              'offset': offset,
            });
          }),
        );

    testWidgets('identidade, um selo só, e o menu sem entradas mortas', (tester) async {
      await abrir(tester, api: apiCom([]));
      expect(find.text('Vitória Leticia'), findsOneWidget);
      expect(find.text('@Vick · vitoria@tobias.dev'), findsOneWidget);
      expect(find.text('Casual'), findsOneWidget);
      expect(find.text('Iniciante'), findsNothing);
      expect(find.text('Recalibrar o TOBIAS'), findsOneWidget);
      expect(find.text('Configurações do perfil'), findsOneWidget);
      expect(find.text('Notificações'), findsNothing);
      expect(find.text('Acessibilidade'), findsNothing);
      expect(find.text('Sair da conta'), findsOneWidget);
    });

    testWidgets('sequência é de dias, não a melhor_sequencia da API', (tester) async {
      // Três sessões em dois dias seguidos (hoje e ontem, ao meio-dia local),
      // cada uma com melhor_sequencia (acertos seguidos) bem diferente.
      final hoje = DateTime.now();
      DateTime dia(int atras) => DateTime(hoje.year, hoje.month, hoje.day - atras, 12);
      await abrir(
        tester,
        api: apiCom(
          [
            _sessaoJson(dia(0), pontos: 1200, melhorSequencia: 9),
            _sessaoJson(dia(1), pontos: 2480, melhorSequencia: 14),
            _sessaoJson(dia(1), pontos: null, melhorSequencia: 11),
          ],
          total: 3,
        ),
        agora: hoje,
      );

      expect(find.text('2 dias'), findsOneWidget);
      for (final errado in ['9 dias', '14 dias', '11 dias', '14', '9']) {
        expect(find.text(errado), findsNothing, reason: errado);
      }
      expect(find.text('3'), findsOneWidget); // sessões
      expect(find.text('2.480'), findsOneWidget); // recorde
    });

    testWidgets('sessões é o total do envelope, não a conta da lista', (tester) async {
      await abrir(tester, api: apiCom([_sessaoJson(DateTime.now(), pontos: 10)], total: 42));
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('cartão do TOBIAS: calibração com data e dificuldade em graus', (tester) async {
      final u = _usuario(calibradoEm: DateTime.now().toUtc(), calibracao: 12.5);
      await abrir(tester, api: apiCom([], eu: u), usuario: u);
      expect(find.textContaining('Calibrado em '), findsOneWidget);
      expect(find.textContaining('dificuldade +12,5°'), findsOneWidget);
      expect(find.textContaining(' g'), findsNothing); // a unidade antiga do Figma
      expect(find.text('Simulador'), findsOneWidget);
      expect(find.text('Calibrar o TOBIAS'), findsNothing);
    });

    testWidgets('cartão do TOBIAS: dificuldade 0 mostra só a data', (tester) async {
      final u = _usuario(calibradoEm: DateTime.now().toUtc(), calibracao: 0);
      await abrir(tester, api: apiCom([], eu: u), usuario: u);
      expect(find.textContaining('Calibrado em '), findsOneWidget);
      expect(find.textContaining('°'), findsNothing);
      expect(find.textContaining('dificuldade'), findsNothing);
    });

    testWidgets('o /eu atualiza a identidade guardada', (tester) async {
      await abrir(
        tester,
        api: apiCom([], eu: _usuario(apelido: 'NovoNoServidor')),
        usuario: _usuario(apelido: 'Antigo'),
      );
      expect(find.text('@NovoNoServidor · vitoria@tobias.dev'), findsOneWidget);
      expect((await AuthStore.lerUsuario())!.apelido, 'NovoNoServidor');
    });

    testWidgets('nunca calibrou: diz isso e oferece calibrar', (tester) async {
      await abrir(tester, api: apiCom([]));
      expect(find.text('Ainda não calibrado'), findsOneWidget);
      expect(find.text('Calibrar o TOBIAS'), findsOneWidget);
    });

    testWidgets('sem rede: identidade aparece, só as estatísticas dão erro', (tester) async {
      var rede = false;
      final api = ApiClient(
        httpClient: MockClient((req) async {
          if (!rede) throw http.ClientException('sem rede');
          if (req.url.path == '/health') return http.Response('{}', 200);
          if (req.url.path == '/v1/auth/eu') return _json(_usuario().toJson());
          return _json({'items': [_sessaoJson(DateTime.now(), pontos: 77)], 'total': 1});
        }),
      );
      await abrir(tester, api: api);

      // A identidade guardada, normal.
      expect(find.text('Vitória Leticia'), findsOneWidget);
      expect(find.text('@Vick · vitoria@tobias.dev'), findsOneWidget);
      expect(find.text('Recalibrar o TOBIAS'), findsOneWidget);
      // Só as estatísticas em erro, com nova tentativa.
      expect(find.byKey(const ValueKey('estatisticas-erro')), findsOneWidget);
      expect(find.text('Estatísticas indisponíveis'), findsOneWidget);
      expect(find.text('Não foi possível conectar ao servidor.'), findsOneWidget);

      rede = true;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('estatisticas-erro')), findsNothing);
      expect(find.text('77'), findsOneWidget); // recorde
    });
  });

  // --------------------------------------------- Configurações do perfil

  group('configurações do perfil', () {
    late List<http.BaseRequest> pedidos;
    late http.Response Function(http.BaseRequest) responder;

    Future<FilaSessoes> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      pedidos = [];
      await AuthStore.salvarToken('t');
      await AuthStore.salvarUsuario(_usuario());
      final fila = FilaSessoes();
      final api = ApiClient(
        httpClient: MockClient((req) async {
          pedidos.add(req);
          return responder(req);
        }),
      );
      final router = GoRouter(
        initialLocation: Routes.perfilConfig,
        routes: [
          GoRoute(path: Routes.perfil, builder: (_, _) => const Scaffold(body: Text('PERFIL'))),
          GoRoute(
            path: Routes.perfilConfig,
            builder: (_, _) => ConfigPerfilScreen(api: api, fila: fila),
          ),
          GoRoute(path: Routes.contaExcluida, builder: (_, _) => const ContaExcluidaScreen()),
          GoRoute(path: Routes.login, builder: (_, _) => const Scaffold(body: Text('LOGIN'))),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return fila;
    }

    testWidgets('não há câmera nem galeria', (tester) async {
      responder = (_) => _json({});
      await abrir(tester);
      expect(find.text('Tirar foto'), findsNothing);
      expect(find.text('Galeria'), findsNothing);
      expect(find.text('Foto de perfil'), findsNothing);
      expect(find.textContaining('É o nome que aparece no ranking'), findsOneWidget);
    });

    testWidgets('apelido duplicado mostra o erro no campo', (tester) async {
      responder = (_) => _json({'detail': 'Apelido ja em uso'}, 409);
      await abrir(tester);
      await tester.enterText(find.byType(TextField).first, 'Joao');
      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      expect(pedidos.single.method, 'PATCH');
      final campo = find.byKey(const ValueKey('campo-apelido'));
      expect(
        find.descendant(of: campo, matching: find.text('Esse apelido já está em uso. Escolha outro.')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('PERFIL'), findsNothing); // continuou na tela
      expect((await AuthStore.lerUsuario())!.apelido, 'Vick');
    });

    testWidgets('apelido novo salva e volta ao Perfil', (tester) async {
      responder = (_) => _json(_usuario(apelido: 'VickAce').toJson());
      await abrir(tester);
      await tester.enterText(find.byType(TextField).first, 'VickAce');
      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      expect(jsonDecode((pedidos.single as http.Request).body), {'apelido': 'VickAce'});
      expect(find.text('PERFIL'), findsOneWidget);
      expect((await AuthStore.lerUsuario())!.apelido, 'VickAce');
    });

    Future<void> abrirDialogo(WidgetTester tester) async {
      await tester.tap(find.text('Excluir minha conta'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir sua conta?'), findsOneWidget);
      expect(find.byKey(const ValueKey('campo-senha-exclusao')), findsOneWidget);
    }

    testWidgets('exclusão: botões na ordem, o destrutivo em segundo', (tester) async {
      responder = (_) => _json({});
      await abrir(tester);
      await abrirDialogo(tester);
      final manter = tester.getCenter(find.text('Não, manter minha conta')).dy;
      final excluir = tester.getCenter(find.text('Sim, excluir')).dy;
      expect(manter < excluir, isTrue);
      expect(find.textContaining('apagados para sempre'), findsOneWidget);
    });

    testWidgets('exclusão sem senha não chama a API', (tester) async {
      responder = (_) => http.Response('', 204);
      await abrir(tester);
      await abrirDialogo(tester);
      await tester.tap(find.text('Sim, excluir'));
      await tester.pumpAndSettle();

      expect(pedidos, isEmpty);
      expect(find.text('Digite sua senha para confirmar.'), findsOneWidget);
      expect(find.text('Excluir sua conta?'), findsOneWidget);
    });

    testWidgets('exclusão com senha errada mostra o erro no diálogo', (tester) async {
      responder = (_) => _json({'detail': 'Credenciais invalidas'}, 401);
      await abrir(tester);
      await abrirDialogo(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('campo-senha-exclusao')),
          matching: find.byType(TextField),
        ),
        'errada123',
      );
      await tester.tap(find.text('Sim, excluir'));
      await tester.pumpAndSettle();

      final req = pedidos.single as http.Request;
      expect((req.method, req.url.path), ('DELETE', '/v1/auth/eu'));
      expect(jsonDecode(req.body), {'senha': 'errada123'});
      expect(find.text('Senha incorreta.'), findsOneWidget);
      expect(find.text('Excluir sua conta?'), findsOneWidget);
      expect(await AuthStore.lerToken(), 't'); // nada foi limpo
    });

    testWidgets('exclusão bem-sucedida limpa a fila e tudo o que é local', (tester) async {
      responder = (_) => http.Response('', 204);
      final fila = await abrir(tester);
      await fila.abrir(
        SessaoLocal(
          uuidSessao: 'pendente-da-conta-apagada',
          treinoVersaoId: 1,
          dificuldade: 0,
          iniciadaEm: '2026-11-05T10:00:00.000Z',
        ),
      );
      await AuthStore.salvarCalibracao(7.5);
      expect(await fila.aguardandoEnvio(), hasLength(1));

      await abrirDialogo(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('campo-senha-exclusao')),
          matching: find.byType(TextField),
        ),
        'senha12345',
      );
      await tester.tap(find.text('Sim, excluir'));
      await tester.pumpAndSettle();

      expect(find.text('Conta excluída'), findsOneWidget);
      expect(await fila.todas(), isEmpty);
      expect(await fila.aguardandoEnvio(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FilaSessoes.chave), isNull);
      expect(await AuthStore.lerToken(), isNull);
      expect(await AuthStore.lerUsuario(), isNull);
      expect(await AuthStore.lerCalibracao(), 0.0);

      await tester.tap(find.text('Voltar ao início'));
      await tester.pumpAndSettle();
      expect(find.text('LOGIN'), findsOneWidget);
    });
  });
}
