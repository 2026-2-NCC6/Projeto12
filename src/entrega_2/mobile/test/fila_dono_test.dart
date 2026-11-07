/// A fila sabe de quem é cada sessão: num celular compartilhado, a sessão de
/// A nunca sobe com o token de B, nem aparece no histórico ou nas pendentes
/// dele, e volta quando A entra de novo.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/auth_store.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/sincronizador.dart';
import 'package:smart_tennis_arena_mobile/state/gravador_sessao.dart';
import 'package:smart_tennis_arena_mobile/state/sessao_ativa.dart';
import 'package:smart_tennis_arena_mobile/transport/device_transport.dart';

const _a = 7;
const _b = 8;

LanceLocal _lance(int bola) => LanceLocal(
  uuidLance: 'lance-$bola-${DateTime.now().microsecondsSinceEpoch}',
  idLanceFirmware: null,
  bola: bola,
  resultado: 'acerto',
  classe: 'medio',
  knockout: false,
  angulo: 45.0,
  tsMs: bola * 3000,
);

SessaoLocal _sessao(String uuid, {int? dono, String inicio = '2026-11-05T10:00:00.000Z'}) =>
    SessaoLocal(
      uuidSessao: uuid,
      treinoVersaoId: 1,
      dificuldade: 0,
      iniciadaEm: inicio,
      usuarioId: dono,
      lances: [_lance(1), _lance(2)],
    );

/// Servidor que aceita tudo e guarda o que recebeu, com qual token.
class _Servidor {
  final recebidas = <(String token, String uuid)>[];

  late final cliente = MockClient((req) async {
    if (req.url.path == '/health') return http.Response('{}', 200);
    final token = req.headers['Authorization']!.replaceFirst('Bearer ', '');
    final sessoes = (jsonDecode(req.body) as Map)['sessoes'] as List;
    return http.Response(
      jsonEncode({
        'sessoes': [
          for (final s in sessoes.cast<Map<String, dynamic>>())
            () {
              recebidas.add((token, s['uuid_sessao'] as String));
              return {
                'uuid_sessao': s['uuid_sessao'],
                'situacao': 'inserida',
                'lances_recebidos': (s['lances'] as List).length,
                'lances_inseridos': (s['lances'] as List).length,
                'lances_duplicados': 0,
                'pontuacao_total': s['pontuacao_cliente'],
              };
            }(),
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  late int? logado;
  late FilaSessoes fila;

  setUp(() {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    logado = null;
    fila = FilaSessoes(donoAtual: () async => logado);
  });

  Future<List<String>> uuids(Future<List<SessaoLocal>> f) async =>
      [for (final s in await f) s.uuidSessao];

  test('sessão de A: B não envia, não vê no histórico nem conta como pendente', () async {
    logado = _a;
    await fila.abrir(_sessao('da-A', dono: _a));
    await fila.abrir(_sessao('separada-de-A', dono: _a));
    await fila.separar('separada-de-A', 'payload_invalido');

    // A sai da conta sem sincronizar; B entra e treina.
    logado = _b;
    await fila.abrir(_sessao('da-B', dono: _b));

    expect((await fila.prepararEnvio()).map((e) => e.uuidSessao), ['da-B']);
    expect(await uuids(fila.historico()), ['da-B']);
    expect(await uuids(fila.aguardandoEnvio()), ['da-B']);
    expect(await fila.separadas(), isEmpty);
    expect(await fila.sessao('da-A'), isNull, reason: 'nem por link direto');

    // Continua guardada, intacta.
    expect(await uuids(fila.todas()), containsAll(['da-A', 'da-B']));

    // A volta: tudo dele reaparece, e o de B some.
    logado = _a;
    expect((await fila.prepararEnvio()).map((e) => e.uuidSessao), ['da-A']);
    expect(await uuids(fila.aguardandoEnvio()), ['da-A']);
    expect(await uuids(fila.historico()), containsAll(['da-A', 'separada-de-A']));
    expect(await uuids(fila.separadas()), ['separada-de-A']);
    expect((await fila.sessao('da-A'))?.uuidSessao, 'da-A');
  });

  test('o envio de B não sobe a sessão de A com o token de B', () async {
    final servidor = _Servidor();
    var token = 'token-de-A';
    Sincronizador sinc() => Sincronizador(
      fila: () => fila,
      api: ApiClient(httpClient: servidor.cliente),
      lerToken: () async => token,
    );

    logado = _a;
    await fila.abrir(_sessao('da-A', dono: _a));
    logado = _b;
    token = 'token-de-B';
    await fila.abrir(_sessao('da-B', dono: _b));

    await sinc().sincronizar();
    expect(servidor.recebidas, [('token-de-B', 'da-B')]);

    // A entra de novo: só então a dele sobe, com o token dele.
    logado = _a;
    token = 'token-de-A';
    await sinc().sincronizar();
    expect(servidor.recebidas, [('token-de-B', 'da-B'), ('token-de-A', 'da-A')]);
  });

  test('o gravador carimba o dono na criação, e ele não muda depois', () async {
    final gravador = GravadorSessao(
      sessao: SessaoAtiva.iniciar(
        PaginaTreinos.fromJson({
          'items': [
            {
              'id': 1,
              'titulo': 'T',
              'descricao': '',
              'escopo': 'pessoal',
              'versao_atual': {
                'id': 1,
                'numero': 1,
                'nivel': 'medio',
                'qtd_lances': 3,
                'intervalo_ms': 3000,
                'falas_tobias': true,
              },
            },
          ],
          'total': 1,
        }).itens.single,
        dificuldade: 0,
      ),
      fila: fila,
      transport: _TobiasMudo(),
      usuarioAtual: () async => _a,
    );
    await gravador.iniciar();
    logado = _b; // trocou de conta antes de sincronizar
    final [s] = await fila.todas();
    expect(s.usuarioId, _a);
    await gravador.encerrar();
  });

  test('o dono padrão é quem está logado no aparelho', () async {
    expect(await AuthStore.lerIdUsuario(), isNull);
    await AuthStore.salvarToken('t');
    await AuthStore.salvarUsuario(
      const UsuarioApi(id: 42, email: 'x@t.dev', papel: 'jogador'),
    );
    expect(await AuthStore.lerIdUsuario(), 42);
    await AuthStore.limparToken();
    expect(await AuthStore.lerIdUsuario(), isNull);
  });

  group('sessões de antes do campo (sem usuario_id)', () {
    Future<void> filaAntiga() async {
      final antiga = _sessao('antiga').toJson()..remove('usuario_id');
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        FilaSessoes.chave: jsonEncode({
          'versao': 1,
          'sessoes': [antiga],
          'separadas': [],
        }),
      });
      fila = FilaSessoes(donoAtual: () async => logado);
    }

    test('são adotadas por quem está logado na primeira leitura', () async {
      await filaAntiga();
      logado = _a;
      expect(await uuids(fila.aguardandoEnvio()), ['antiga']);

      // O dono foi gravado: uma fila nova (app reaberto) já a vê como de A.
      final bruto = (await SharedPreferences.getInstance()).getString(FilaSessoes.chave)!;
      expect((jsonDecode(bruto)['sessoes'] as List).single['usuario_id'], _a);

      // E depois de adotada, B não a vê.
      logado = _b;
      expect(await fila.aguardandoEnvio(), isEmpty);
      expect(await fila.prepararEnvio(), isEmpty);
    });

    test('sem ninguém logado, não são adotadas por ninguém', () async {
      await filaAntiga();
      logado = null;
      expect(await uuids(fila.aguardandoEnvio()), ['antiga']);
      expect((await fila.todas()).single.usuarioId, isNull);
      // O primeiro login é que adota.
      logado = _b;
      expect(await uuids(fila.aguardandoEnvio()), ['antiga']);
      expect((await fila.todas()).single.usuarioId, _b);
    });
  });

  test('o limite de pendentes é por dono: B não descarta as de A', () async {
    fila = FilaSessoes(limitePendentes: 2, donoAtual: () async => logado);
    logado = _a;
    await fila.abrir(_sessao('a1', dono: _a, inicio: '2026-11-01T10:00:00.000Z'));
    await fila.abrir(_sessao('a2', dono: _a, inicio: '2026-11-02T10:00:00.000Z'));
    logado = _b;
    for (var i = 1; i <= 5; i++) {
      await fila.abrir(_sessao('b$i', dono: _b, inicio: '2026-11-0${i + 2}T10:00:00.000Z'));
    }
    expect(await uuids(fila.aguardandoEnvio()), ['b4', 'b5']);
    logado = _a;
    expect(await uuids(fila.aguardandoEnvio()), ['a1', 'a2']);
  });
}

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
