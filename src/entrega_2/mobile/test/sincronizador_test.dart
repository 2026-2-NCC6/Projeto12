import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/sincronizador.dart';

/// Servidor falso. [responder] recebe as sessões de cada POST e devolve
/// (status, corpo). Registra todas as requisições, em ordem.
class _Servidor {
  _Servidor(this.responder);

  FutureOr<(int, Object)> Function(List<Map<String, dynamic>> sessoes)
  responder;
  final requisicoes = <http.Request>[];

  Iterable<http.Request> get posts =>
      requisicoes.where((r) => r.method == 'POST');

  late final cliente = MockClient((req) async {
    requisicoes.add(req);
    if (req.url.path == '/health') return http.Response('{"status":"ok"}', 200);
    final sessoes = ((jsonDecode(req.body) as Map)['sessoes'] as List)
        .cast<Map<String, dynamic>>();
    final (status, corpo) = await responder(sessoes);
    return http.Response(jsonEncode(corpo), status);
  });
}

/// 200 com a mesma situação para todas as sessões do lote.
(int, Object) _todas(
  List<Map<String, dynamic>> sessoes,
  String situacao, {
  int pontos = 145,
}) => (
  200,
  {
    'sessoes': [
      for (final s in sessoes)
        {
          'uuid_sessao': s['uuid_sessao'],
          'situacao': situacao,
          'motivo': situacao == 'rejeitada' ? 'versao_invalida' : null,
          'lances_recebidos': (s['lances'] as List).length,
          'lances_inseridos': 0,
          'lances_duplicados': 0,
          'pontuacao_total': situacao == 'rejeitada' ? null : pontos,
        },
    ],
  },
);

SessaoLocal _sessao(String uuid, {int dia = 1, double angulo = 61.4}) =>
    SessaoLocal(
      uuidSessao: uuid,
      treinoVersaoId: 5,
      dificuldade: 2.5,
      iniciadaEm: '2026-10-${dia.toString().padLeft(2, '0')}T11:15:00.000Z',
      encerradaEm: '2026-10-${dia.toString().padLeft(2, '0')}T11:20:00.000Z',
      lances: [
        LanceLocal(
          uuidLance: '$uuid-l1',
          idLanceFirmware: 'L-14230-1',
          bola: 1,
          resultado: 'acerto',
          classe: 'forte',
          knockout: true,
          angulo: angulo,
          tsMs: 1500,
        ),
      ],
    );

Sincronizador _sinc(
  _Servidor servidor,
  FilaSessoes fila, {
  String? token = 'token-valido',
  Future<String?> Function()? renovar,
}) => Sincronizador(
  fila: () => fila,
  api: ApiClient(httpClient: servidor.cliente),
  lerToken: () async => token,
  renovarToken: renovar,
);

void main() {
  late FilaSessoes fila;

  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    fila = FilaSessoes();
  });

  test('envio bem-sucedido marca como sincronizada e guarda a pontuação', () async {
    await fila.abrir(_sessao('a'));
    await fila.abrir(_sessao('b', dia: 2));
    final servidor = _Servidor(
      (s) => (
        200,
        {
          'sessoes': [
            {..._todas([s[0]], 'inserida', pontos: 245).$2.sessoes.single},
            {..._todas([s[1]], 'ja_existia', pontos: 20).$2.sessoes.single},
          ],
        },
      ),
    );

    final r = await _sinc(servidor, fila).sincronizar();

    expect(r, ResultadoSincronizacao.concluida);
    final todas = await fila.todas();
    expect(todas.every((s) => s.sincronizada), isTrue);
    expect([for (final s in todas) s.pontuacaoServidor], [245, 20]);
    // Ficam na fila (histórico local), só não aguardam mais envio.
    expect(todas, hasLength(2));
    expect(await fila.aguardandoEnvio(), isEmpty);
  });

  test('corpo do envio: contrato da API, com pontuacao_cliente, ângulo intacto', () async {
    await fila.abrir(_sessao('a'));
    final servidor = _Servidor((s) => _todas(s, 'inserida'));

    await _sinc(servidor, fila).sincronizar();

    // Acorda a API antes de enviar.
    expect(servidor.requisicoes.first.url.path, '/health');
    final post = servidor.posts.single;
    expect(post.url.path, '/v1/sessions');
    expect(post.headers['Authorization'], 'Bearer token-valido');
    final sessao = ((jsonDecode(post.body) as Map)['sessoes'] as List).single as Map;
    expect(sessao.keys.toSet(), {
      'uuid_sessao',
      'treino_versao_id',
      'dificuldade',
      'iniciada_em',
      'encerrada_em',
      'pontuacao_cliente',
      'lances',
    });
    expect(sessao['dificuldade'], 2.5);
    expect(sessao['iniciada_em'], endsWith('Z'));
    expect(post.body, contains('"angulo":61.4'));
    // O total da regra local, inteiro. Nada dos campos só do aparelho.
    expect(sessao['pontuacao_cliente'], isA<int>());
    expect(sessao['pontuacao_cliente'], _sessao('a').pontuar().pontuacaoTotal);
    expect(post.body, isNot(contains('pontuacao_servidor')));
    expect(post.body, isNot(contains('sincronizada')));
  });

  group('divergência de pontuação', () {
    Future<(List<String>, List<String>)> enviar(int Function(int) servidor) async {
      await fila.abrir(_sessao('a'));
      final logs = <String>[];
      final printOriginal = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {
        if (m != null) logs.add(m);
      };
      final sinc = _sinc(
        _Servidor(
          (s) => _todas(
            s,
            'inserida',
            pontos: servidor(s.single['pontuacao_cliente'] as int),
          ),
        ),
        fila,
      );
      final avisos = <String>[];
      final sub = sinc.avisos.listen(avisos.add);
      try {
        await sinc.sincronizar();
        await Future<void>.delayed(Duration.zero);
      } finally {
        debugPrint = printOriginal;
        await sub.cancel();
      }
      return (logs, avisos);
    }

    test('diferente: vale a do servidor, registra em log, sem aviso', () async {
      final local = _sessao('a').pontuar().pontuacaoTotal;
      final (logs, avisos) = await enviar((cliente) => cliente + 1);

      final s = (await fila.todas()).single;
      expect(s.pontuacaoServidor, local + 1);
      expect(s.pontuacaoExibida, local + 1);
      expect(
        logs.where((l) => l.contains('PONTUAÇÃO DIVERGENTE')).single,
        allOf(contains('app=$local'), contains('servidor=${local + 1}')),
      );
      expect(avisos, isEmpty);
    });

    test('igual (o caso normal): nenhum log de divergência', () async {
      final (logs, avisos) = await enviar((cliente) => cliente);

      expect(logs.where((l) => l.contains('DIVERGENTE')), isEmpty);
      expect(avisos, isEmpty);
      expect((await fila.todas()).single.sincronizada, isTrue);
    });
  });

  test('até 50 sessões por lote', () async {
    final grande = FilaSessoes(limitePendentes: 200);
    for (var i = 0; i < 120; i++) {
      await grande.abrir(_sessao('s$i', dia: 1 + i % 28));
    }
    final servidor = _Servidor((s) => _todas(s, 'inserida'));

    await _sinc(servidor, grande).sincronizar();

    final tamanhos = [
      for (final p in servidor.posts)
        ((jsonDecode(p.body) as Map)['sessoes'] as List).length,
    ];
    expect(tamanhos, [50, 50, 20]);
  });

  test('dois envios ao mesmo tempo viram um só', () async {
    await fila.abrir(_sessao('a'));
    final liberar = Completer<void>();
    final servidor = _Servidor((s) async {
      await liberar.future;
      return _todas(s, 'inserida');
    });
    final sinc = _sinc(servidor, fila);

    final primeiro = sinc.sincronizar();
    final segundo = sinc.sincronizar();
    expect(identical(primeiro, segundo), isTrue);
    liberar.complete();
    await Future.wait([primeiro, segundo]);

    expect(servidor.posts, hasLength(1));
  });

  test('422 numa sessão: separada e não reenviada em laço', () async {
    await fila.abrir(_sessao('ruim'));
    final servidor = _Servidor((_) => (422, {'detail': []}));
    final sinc = _sinc(servidor, fila);

    await sinc.sincronizar();
    await sinc.sincronizar();
    await sinc.sincronizar();

    expect(servidor.posts, hasLength(1));
    expect(await fila.todas(), isEmpty);
    final s = (await fila.separadas()).single;
    expect(s.uuidSessao, 'ruim');
    expect(s.falha, 'payload_invalido');
    expect(s.sincronizada, isFalse);
    expect(await fila.aguardandoEnvio(), isEmpty);
  });

  test('422 num lote: acha a sessão ruim uma a uma e envia as boas', () async {
    await fila.abrir(_sessao('boa'));
    await fila.abrir(_sessao('ruim', dia: 2));
    final servidor = _Servidor((s) {
      if (s.length > 1 || s.single['uuid_sessao'] == 'ruim') {
        return (422, {'detail': []});
      }
      return _todas(s, 'inserida');
    });

    await _sinc(servidor, fila).sincronizar();

    expect((await fila.todas()).single.uuidSessao, 'boa');
    expect((await fila.todas()).single.sincronizada, isTrue);
    expect((await fila.separadas()).single.uuidSessao, 'ruim');
    expect((await fila.separadas()).single.falha, 'payload_invalido');
    expect(servidor.posts, hasLength(3)); // o lote e depois uma a uma
  });

  test('rejeitada sai da fila, avisa o usuário e não é reenviada', () async {
    await fila.abrir(_sessao('alheia'));
    final servidor = _Servidor((s) => _todas(s, 'rejeitada'));
    final sinc = _sinc(servidor, fila);
    final avisos = <String>[];
    final sub = sinc.avisos.listen(avisos.add);

    await sinc.sincronizar();
    await sinc.sincronizar();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(await fila.todas(), isEmpty);
    expect(avisos, hasLength(1));
    expect(avisos.single, contains('descartada'));
    expect(servidor.posts, hasLength(1));
  });

  test('retenção: guarda as 10 sincronizadas mais recentes', () async {
    for (var dia = 1; dia <= 12; dia++) {
      await fila.abrir(_sessao('dia$dia', dia: dia));
    }
    final servidor = _Servidor((s) => _todas(s, 'inserida'));

    await _sinc(servidor, fila).sincronizar();

    final restantes = [for (final s in await fila.todas()) s.uuidSessao];
    expect(restantes, hasLength(10));
    expect(restantes, isNot(contains('dia1')));
    expect(restantes, isNot(contains('dia2')));
    expect(restantes, contains('dia12'));
  });

  test('retenção não descarta pendentes para abrir espaço', () async {
    for (var dia = 1; dia <= 10; dia++) {
      await fila.abrir(_sessao('sinc$dia', dia: dia));
    }
    await _sinc(_Servidor((s) => _todas(s, 'inserida')), fila).sincronizar();
    // Uma pendente nova, que o servidor recusa temporariamente.
    await fila.abrir(_sessao('pendente', dia: 20));
    final sinc = _sinc(_Servidor((_) => (503, {'detail': 'x'})), fila);
    await sinc.sincronizar();
    sinc.cancelarAgendamento();

    final todas = await fila.todas();
    expect(todas.where((s) => s.sincronizada), hasLength(10));
    expect(todas.where((s) => !s.sincronizada).single.uuidSessao, 'pendente');
  });

  test('5xx: tenta de novo com espera exponencial, variação e teto de 5 min', () async {
    await fila.abrir(_sessao('a'));
    var status = 503;
    final servidor = _Servidor(
      (s) => status == 200 ? _todas(s, 'inserida') : (status, {'detail': 'x'}),
    );
    final sinc = _sinc(servidor, fila);

    final esperas = <Duration>[];
    for (var i = 0; i < 12; i++) {
      expect(await sinc.sincronizar(), ResultadoSincronizacao.tentaraDeNovo);
      esperas.add(sinc.ultimaEspera!);
    }
    sinc.cancelarAgendamento();

    // 1ª entre 1 e 2 s (base de ~2 s, metade sorteada)...
    expect(esperas[0].inMilliseconds, inInclusiveRange(1000, 2000));
    // ...dobrando...
    expect(esperas[3].inMilliseconds, inInclusiveRange(8000, 16000));
    // ...até o teto de 5 min.
    for (final e in esperas) {
      expect(e, lessThanOrEqualTo(const Duration(minutes: 5)));
    }
    expect(esperas.last, greaterThanOrEqualTo(const Duration(seconds: 150)));
    expect((await fila.todas()).single.sincronizada, isFalse);

    // Voltou: envia e a espera recomeça do início.
    status = 200;
    expect(await sinc.sincronizar(), ResultadoSincronizacao.concluida);
    expect((await fila.todas()).single.sincronizada, isTrue);
    await fila.abrir(_sessao('b', dia: 2));
    status = 500;
    await sinc.sincronizar();
    sinc.cancelarAgendamento();
    expect(sinc.ultimaEspera, lessThanOrEqualTo(const Duration(seconds: 2)));
  });

  test('rede fora (timeout/conexão) também é temporário', () async {
    await fila.abrir(_sessao('a'));
    final cliente = MockClient((req) async {
      if (req.url.path == '/health') return http.Response('{}', 200);
      throw http.ClientException('sem rede');
    });
    final sinc = Sincronizador(
      fila: () => fila,
      api: ApiClient(httpClient: cliente),
      lerToken: () async => 't',
    );

    expect(await sinc.sincronizar(), ResultadoSincronizacao.tentaraDeNovo);
    sinc.cancelarAgendamento();
    expect((await fila.todas()).single.sincronizada, isFalse);
  });

  group('separadas (422)', () {
    test('não ocupam vaga das pendentes: 20 boas + separadas, nada some', () async {
      final sinc = _sinc(_Servidor((_) => (422, {'detail': []})), fila);
      for (var dia = 1; dia <= 3; dia++) {
        await fila.abrir(_sessao('ruim$dia', dia: dia));
        await sinc.sincronizar();
      }
      for (var dia = 10; dia < 30; dia++) {
        await fila.abrir(_sessao('boa$dia', dia: dia));
      }

      expect(await fila.aguardandoEnvio(), hasLength(20));
      expect(await fila.separadas(), hasLength(3));
    });

    test('limite próprio de 5: as mais antigas saem', () async {
      final sinc = _sinc(_Servidor((_) => (422, {'detail': []})), fila);
      for (var dia = 1; dia <= 7; dia++) {
        await fila.abrir(_sessao('ruim$dia', dia: dia));
        await sinc.sincronizar();
      }

      final uuids = [for (final s in await fila.separadas()) s.uuidSessao];
      expect(uuids, ['ruim3', 'ruim4', 'ruim5', 'ruim6', 'ruim7']);
    });

    test('ficam separadas depois de reabrir o app', () async {
      await fila.abrir(_sessao('ruim'));
      await _sinc(_Servidor((_) => (422, {'detail': []})), fila).sincronizar();

      final reaberta = FilaSessoes();
      expect(await reaberta.aguardandoEnvio(), isEmpty);
      expect((await reaberta.separadas()).single.uuidSessao, 'ruim');
      expect(await reaberta.sessao('ruim'), isNotNull);
    });

    test('fila antiga, com separadas misturadas às pendentes, é migrada', () async {
      final antiga = _sessao('antiga')..falha = 'payload_invalido';
      SharedPreferences.setMockInitialValues({
        FilaSessoes.chave: jsonEncode({
          'versao': 1,
          'sessoes': [antiga.toJson(), _sessao('boa', dia: 2).toJson()],
        }),
      });

      final f = FilaSessoes();
      expect([for (final s in await f.aguardandoEnvio()) s.uuidSessao], ['boa']);
      expect((await f.separadas()).single.uuidSessao, 'antiga');
    });

    test('422 é registrado em destaque com o uuid e a resposta', () async {
      final logs = <String>[];
      final printOriginal = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {
        if (m != null) logs.add(m);
      };
      try {
        await fila.abrir(_sessao('ruim'));
        await _sinc(
          _Servidor(
            (_) => (
              422,
              {
                'detail': [
                  {'loc': ['body', 'sessoes', 0, 'dificuldade'], 'msg': 'x'},
                ],
              },
            ),
          ),
          fila,
        ).sincronizar();
      } finally {
        debugPrint = printOriginal;
      }

      final log = logs.singleWhere((l) => l.contains('BUG DO APP'));
      expect(log, contains('uuid_sessao: ruim'));
      expect(log, contains('dificuldade'));
    });
  });

  group('aviso de rejeitada usa o motivo', () {
    test('versao_invalida', () {
      expect(
        Sincronizador.avisoDeRejeitada('versao_invalida'),
        contains('o treino dela não existe mais'),
      );
    });

    test('qualquer outro motivo: frase genérica', () {
      for (final motivo in [null, 'outro_motivo']) {
        expect(
          Sincronizador.avisoDeRejeitada(motivo),
          'Uma sessão foi recusada pelo servidor e descartada.',
        );
      }
    });

    test('o aviso emitido vem do motivo da resposta', () async {
      await fila.abrir(_sessao('alheia'));
      final sinc = _sinc(_Servidor((s) => _todas(s, 'rejeitada')), fila);
      final avisos = <String>[];
      final sub = sinc.avisos.listen(avisos.add);

      await sinc.sincronizar();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(avisos.single, Sincronizador.avisoDeRejeitada('versao_invalida'));
    });
  });

  test('pedir login zera a espera: a próxima falha recomeça de ~2 s', () async {
    await fila.abrir(_sessao('a'));
    var status = 503;
    final sinc = _sinc(_Servidor((_) => (status, {'detail': 'x'})), fila);
    for (var i = 0; i < 6; i++) {
      await sinc.sincronizar();
    }
    expect(sinc.ultimaEspera, greaterThan(const Duration(seconds: 16)));

    status = 401;
    expect(await sinc.sincronizar(), ResultadoSincronizacao.precisaLogin);
    status = 503;
    await sinc.sincronizar();
    sinc.cancelarAgendamento();

    expect(sinc.ultimaEspera, lessThanOrEqualTo(const Duration(seconds: 2)));
  });

  group('401', () {
    test('renova o login e tenta de novo uma vez', () async {
      await fila.abrir(_sessao('a'));
      final servidor = _Servidor((s) => _todas(s, 'inserida'));
      servidor.responder = (s) => servidor.posts.last.headers['Authorization'] ==
              'Bearer token-novo'
          ? _todas(s, 'inserida')
          : (401, {'detail': 'Token invalido ou expirado'});
      var renovacoes = 0;

      final r = await _sinc(
        servidor,
        fila,
        token: 'expirado',
        renovar: () async {
          renovacoes++;
          return 'token-novo';
        },
      ).sincronizar();

      expect(r, ResultadoSincronizacao.concluida);
      expect(renovacoes, 1);
      expect(servidor.posts, hasLength(2));
    });

    test('se continuar 401, para sem laço e pede login', () async {
      await fila.abrir(_sessao('a'));
      final servidor = _Servidor((_) => (401, {'detail': 'x'}));

      final r = await _sinc(
        servidor,
        fila,
        renovar: () async => 'outro',
      ).sincronizar();

      expect(r, ResultadoSincronizacao.precisaLogin);
      expect(servidor.posts, hasLength(2));
      expect((await fila.todas()).single.sincronizada, isFalse);
    });

    test('sem como renovar (o padrão do app): pede login, sessão fica', () async {
      await fila.abrir(_sessao('a'));
      final servidor = _Servidor((_) => (401, {'detail': 'x'}));
      final sinc = _sinc(servidor, fila);
      final avisos = <String>[];
      final sub = sinc.avisos.listen(avisos.add);

      expect(await sinc.sincronizar(), ResultadoSincronizacao.precisaLogin);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(servidor.posts, hasLength(1));
      expect(avisos.single, contains('Entre de novo'));
      expect(await fila.aguardandoEnvio(), hasLength(1));
    });
  });

  test('sem token: não envia nada', () async {
    await fila.abrir(_sessao('a'));
    final servidor = _Servidor((s) => _todas(s, 'inserida'));

    final r = await _sinc(servidor, fila, token: null).sincronizar();

    expect(r, ResultadoSincronizacao.precisaLogin);
    expect(servidor.requisicoes, isEmpty);
  });

  test('lance que chega durante o envio mantém a sessão pendente', () async {
    await fila.abrir(_sessao('a'));
    var primeiroEnvio = true;
    final servidor = _Servidor((s) async {
      if (!primeiroEnvio) return _todas(s, 'ja_existia');
      primeiroEnvio = false;
      // O treino continua enquanto a primeira requisição está no ar.
      await fila.registrarLance(
        'a',
        const LanceLocal(
          uuidLance: 'a-l2',
          idLanceFirmware: 'L-17000-2',
          bola: 2,
          resultado: 'erro',
          classe: 'sem_impacto',
          knockout: false,
          angulo: 0.0,
          tsMs: 4500,
        ),
      );
      return _todas(s, 'inserida');
    });
    final sinc = _sinc(servidor, fila);

    await sinc.sincronizar();
    final depois = (await fila.todas()).single;
    expect(depois.sincronizada, isFalse, reason: 'o lance 2 não foi enviado');

    await sinc.sincronizar();
    expect((await fila.todas()).single.sincronizada, isTrue);
    final segundo = servidor.posts.last.body;
    expect(segundo, contains('a-l2'));
  });

  test('sessão sincronizada que recebe lance volta a ficar pendente', () async {
    await fila.abrir(_sessao('a'));
    await _sinc(_Servidor((s) => _todas(s, 'inserida')), fila).sincronizar();
    expect(await fila.aguardandoEnvio(), isEmpty);

    await fila.encerrar('a', DateTime.utc(2026, 10, 1, 11, 30));

    expect(await fila.aguardandoEnvio(), hasLength(1));
  });
}

extension on Object {
  /// Atalho para o corpo de `_todas`.
  List<Map<String, dynamic>> get sessoes =>
      ((this as Map)['sessoes'] as List).cast<Map<String, dynamic>>();
}
