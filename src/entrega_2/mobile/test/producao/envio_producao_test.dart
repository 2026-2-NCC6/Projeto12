// Verificação MANUAL contra a API de PRODUÇÃO. Fica pulada na suíte normal;
// só roda com as credenciais no ambiente:
//
//   $env:TOBIAS_EMAIL='...'; $env:TOBIAS_SENHA='...'
//   flutter test test/producao/envio_producao_test.dart
//
// Mesmo caminho do app, sem a interface: SessaoAtiva (congelada) →
// GravadorSessao com o MockTransport (o simulador) → FilaSessoes →
// Sincronizador → ApiClient. Cada teste grava UMA sessão real no banco de
// produção.
//
// O print é a saída do script: o uuid e as respostas, para conferir no banco.
// ignore_for_file: avoid_print
@Tags(['producao'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/api_config.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/sincronizador.dart';
import 'package:smart_tennis_arena_mobile/state/gravador_sessao.dart';
import 'package:smart_tennis_arena_mobile/state/sessao_ativa.dart';
import 'package:smart_tennis_arena_mobile/transport/mock_transport.dart';

final _email = Platform.environment['TOBIAS_EMAIL'];
final _senha = Platform.environment['TOBIAS_SENHA'];
final _pular = _email == null || _senha == null
    ? 'defina TOBIAS_EMAIL e TOBIAS_SENHA para rodar contra produção'
    : false;

/// Login, e uma sessão completa no simulador gravada em [fila]. Devolve o
/// token e o `uuid_sessao`.
Future<(String, String)> _sessaoNoSimulador(
  ApiClient api,
  FilaSessoes fila,
) async {
  print('API: ${ApiConfig.baseUrl}');
  await api.acordarApi();
  final token = await api.login(_email!, _senha!);
  final usuario = await api.eu(token);
  final treinos = (await api.listarTreinos(token)).itens
      .where((t) => t.versaoId != null)
      .toList();
  expect(treinos, isNotEmpty, reason: 'a conta não tem treino da API');
  final treino = treinos.first;

  final sessao = SessaoAtiva.iniciar(treino, dificuldade: usuario.calibracao);
  final gravador = GravadorSessao(
    sessao: sessao,
    fila: fila,
    transport: MockTransport(),
  );
  await gravador.iniciar();
  final uuid = gravador.uuidSessao;
  print('uuid_sessao: $uuid');
  print(
    'treino: "${treino.titulo}" · treino_versao_id: '
    '${sessao.treinoVersaoId} · ${sessao.lances} lances · '
    'dificuldade: ${sessao.dificuldade}',
  );
  final limite = DateTime.now().add(const Duration(minutes: 3));
  while (gravador.lancesGravados.value < sessao.lances &&
      DateTime.now().isBefore(limite)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  await gravador.encerrar();
  print('lances gravados: ${(await fila.sessao(uuid))!.lances.length}');
  return (token, uuid);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'caminho normal: pontuacao_cliente igual ao oficial; reenvio ja_existia',
    () async {
      final api = ApiClient();
      final fila = FilaSessoes();
      final (token, uuid) = await _sessaoNoSimulador(api, fila);
      final gravada = (await fila.sessao(uuid))!;

      // Sincroniza pelo Sincronizador, como o fim da sessão dispara.
      final sinc = Sincronizador(
        fila: () => fila,
        api: api,
        lerToken: () async => token,
      );
      final avisos = <String>[];
      sinc.avisos.listen(avisos.add);
      final resultado = await sinc.sincronizar();
      sinc.cancelarAgendamento();
      final depois = (await fila.sessao(uuid))!;
      final local = depois.pontuar().pontuacaoTotal;
      print(
        'envio 1: $resultado · sincronizada: ${depois.sincronizada} · '
        'pontuacao_cliente: $local · pontuacao_total: '
        '${depois.pontuacaoServidor} · avisos: $avisos',
      );
      expect(resultado, ResultadoSincronizacao.concluida);
      expect(depois.sincronizada, isTrue);
      expect(await fila.separadas(), isEmpty);
      expect(depois.pontuacaoServidor, local);

      // Sincronizar de novo: nada pendente, então nenhum POST.
      expect(await sinc.sincronizar(), ResultadoSincronizacao.concluida);

      // Reenvio forçado do MESMO corpo: tem de vir ja_existia, com todos
      // os lances reconhecidos como duplicados (nada inserido de novo).
      final reenvio = (await api.enviarSessoes(token, [
        depois.paraEnvio(),
      ])).single;
      print('envio 2 (forçado): $reenvio');
      expect(reenvio['uuid_sessao'], uuid);
      expect(reenvio['situacao'], 'ja_existia');
      expect(reenvio['lances_inseridos'], 0);
      expect(reenvio['lances_duplicados'], gravada.lances.length);
      expect(reenvio['pontuacao_total'], local);
    },
    skip: _pular,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
