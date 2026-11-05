import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pontuacao.dart';

/// Um lance como foi recebido, com o UUID gerado NA CHEGADA.
///
/// As chaves do JSON são as do contrato `POST /v1/sessions` (US-704), para
/// a etapa de envio não precisar traduzir nada.
class LanceLocal {
  const LanceLocal({
    required this.uuidLance,
    required this.idLanceFirmware,
    required this.bola,
    required this.resultado,
    required this.classe,
    required this.knockout,
    required this.angulo,
    required this.tsMs,
  });

  factory LanceLocal.fromJson(Map<String, dynamic> j) => LanceLocal(
    uuidLance: j['uuid_lance'] as String,
    idLanceFirmware: j['id_lance_firmware'] as String?,
    bola: j['bola'] as int,
    resultado: j['resultado'] as String,
    classe: j['classe'] as String,
    knockout: j['knockout'] as bool,
    angulo: j['angulo'] as num,
    tsMs: j['ts_ms'] as int,
  );

  final String uuidLance;

  /// `L-<millis>-<bolaFirmware>`: guarda o relógio e a contagem do firmware,
  /// que o app não usa (ambos reiniciam numa pausa).
  final String? idLanceFirmware;

  /// Contador do app, de 1 a N, contínuo através das pausas.
  final int bola;
  final String resultado;
  final String classe;
  final bool knockout;

  /// Exatamente como veio do firmware (já com 1 casa decimal). Nenhuma
  /// aritmética aqui: qualquer conta pode criar casas que a API recusa.
  final num angulo;

  /// Milissegundos desde o início da sessão, no relógio do app.
  final int tsMs;

  Map<String, dynamic> toJson() => {
    'uuid_lance': uuidLance,
    'id_lance_firmware': idLanceFirmware,
    'bola': bola,
    'resultado': resultado,
    'classe': classe,
    'knockout': knockout,
    'angulo': angulo,
    'ts_ms': tsMs,
  };
}

/// Uma sessão guardada no aparelho até ser sincronizada.
class SessaoLocal {
  SessaoLocal({
    required this.uuidSessao,
    required this.treinoVersaoId,
    required this.dificuldade,
    required this.iniciadaEm,
    this.encerradaEm,
    this.sincronizada = false,
    this.pontuacaoServidor,
    this.falha,
    this.treinoTitulo,
    List<LanceLocal>? lances,
  }) : lances = lances ?? [];

  factory SessaoLocal.fromJson(Map<String, dynamic> j) => SessaoLocal(
    uuidSessao: j['uuid_sessao'] as String,
    treinoVersaoId: j['treino_versao_id'] as int,
    dificuldade: j['dificuldade'] as num,
    iniciadaEm: j['iniciada_em'] as String,
    encerradaEm: j['encerrada_em'] as String?,
    sincronizada: j['sincronizada'] as bool,
    // Ausentes nas filas gravadas antes da etapa 5.
    pontuacaoServidor: j['pontuacao_servidor'] as int?,
    falha: j['falha'] as String?,
    // Ausente nas filas gravadas antes da etapa 7.
    treinoTitulo: j['treino_titulo'] as String?,
    lances: [
      for (final l in (j['lances'] as List).cast<Map<String, dynamic>>())
        LanceLocal.fromJson(l),
    ],
  );

  final String uuidSessao;
  final int treinoVersaoId;
  final num dificuldade;

  /// ISO 8601 em UTC (sufixo `Z`): fuso explícito, como a API exige.
  final String iniciadaEm;
  String? encerradaEm;
  bool sincronizada;

  /// `pontuacao_total` oficial devolvido pela API no envio.
  int? pontuacaoServidor;

  /// Erro permanente (ex.: `payload_invalido` num 422): a sessão vai para
  /// as separadas da fila, guardada mas fora do envio, para não reenviar em
  /// laço.
  String? falha;

  /// Nome do treino no início da sessão, para o histórico local. Só do
  /// aparelho: não vai no envio (o servidor tem a versão do treino).
  final String? treinoTitulo;

  final List<LanceLocal> lances;

  /// Muda a cada alteração da sessão, só em memória. O envio só marca a
  /// sessão como sincronizada se ela não mudou desde que o corpo foi
  /// montado (ex.: chegou um lance durante a requisição).
  int _versao = 0;

  /// A pontuação pela regra oficial ([calcularPontuacao], a mesma do
  /// servidor), sobre os lances gravados até agora.
  ResultadoPontuacao pontuar() => calcularPontuacao(
    [
      for (final l in lances)
        LanceBruto(
          bola: l.bola,
          resultado: ResultadoLance.values.byName(l.resultado),
          anguloDecimos: decimos(l.angulo),
        ),
    ],
    dificuldadeDecimos: decimos(dificuldade),
  );

  /// O placar que vale: o oficial do servidor depois de sincronizada; o
  /// local enquanto pendente. Recálculo autoritativo: quem tem a palavra
  /// final é o servidor.
  int get pontuacaoExibida =>
      sincronizada && pontuacaoServidor != null
      ? pontuacaoServidor!
      : pontuar().pontuacaoTotal;

  /// O corpo de `POST /v1/sessions` para esta sessão: só o contrato, sem os
  /// campos locais (sincronizada, pontuação do servidor, falha).
  ///
  /// `pontuacao_cliente` é o total local, para o servidor detectar
  /// divergência entre a regra do app e a dele. Ele nunca o grava como
  /// oficial.
  Map<String, dynamic> paraEnvio() => {
    'uuid_sessao': uuidSessao,
    'treino_versao_id': treinoVersaoId,
    'dificuldade': dificuldade,
    'iniciada_em': iniciadaEm,
    'encerrada_em': encerradaEm,
    'pontuacao_cliente': pontuar().pontuacaoTotal,
    'lances': [for (final l in lances) l.toJson()],
  };

  Map<String, dynamic> toJson() => {
    'uuid_sessao': uuidSessao,
    'treino_versao_id': treinoVersaoId,
    'dificuldade': dificuldade,
    'iniciada_em': iniciadaEm,
    'encerrada_em': encerradaEm,
    'sincronizada': sincronizada,
    'pontuacao_servidor': pontuacaoServidor,
    'falha': falha,
    'treino_titulo': treinoTitulo,
    'lances': [for (final l in lances) l.toJson()],
  };
}

/// Uma sessão pronta para envio: o corpo e a versão em que foi montado.
class EnvioPreparado {
  const EnvioPreparado(this.uuidSessao, this.versao, this.corpo);

  final String uuidSessao;
  final int versao;
  final Map<String, dynamic> corpo;
}

/// Resultado de uma sessão na resposta da API.
class RespostaSessao {
  const RespostaSessao({
    required this.uuidSessao,
    required this.situacao,
    this.motivo,
    this.pontuacaoTotal,
  });

  factory RespostaSessao.fromJson(Map<String, dynamic> j) => RespostaSessao(
    uuidSessao: j['uuid_sessao'] as String,
    situacao: j['situacao'] as String,
    motivo: j['motivo'] as String?,
    pontuacaoTotal: j['pontuacao_total'] as int?,
  );

  final String uuidSessao;

  /// `inserida` | `ja_existia` | `rejeitada`.
  final String situacao;

  /// Por que foi rejeitada. Hoje só `versao_invalida` (versão do treino que
  /// não existe ou é de outro dono); nulo nas aceitas.
  final String? motivo;
  final int? pontuacaoTotal;
}

/// Data/hora com fuso explícito (UTC, sufixo `Z`). O `toIso8601String()` de
/// uma data local sai SEM fuso, e a API recusa isso com 422.
String isoComFuso(DateTime instante) => instante.toUtc().toIso8601String();

/// Fila de sessões do aparelho, em JSON no `shared_preferences`.
///
/// Dois espaços, cada um com seu limite:
/// - `sessoes`: as pendentes (até [limitePendentes]) e as sincronizadas
///   (histórico local, até [limiteSincronizadas]);
/// - `separadas`: as que a API recusou com 422 (até [limiteSeparadas]).
///   Ficam à parte para que sessões com defeito permanente não ocupem as
///   vagas das pendentes e empurrem sessões boas para fora.
///
/// Cada alteração regrava a fila inteira (poucos KB). As gravações passam
/// por uma fila serial: dois lances chegando juntos não podem ler o mesmo
/// estado e um apagar o outro.
class FilaSessoes {
  FilaSessoes({
    this.limitePendentes = 20,
    this.limiteSincronizadas = 10,
    this.limiteSeparadas = 5,
  });

  /// A fila do app. Uma instância só: a serialização das gravações vale
  /// dentro de uma instância, então duas instâncias concorrentes poderiam
  /// se sobrescrever.
  static FilaSessoes get doApp => _doApp;
  static FilaSessoes _doApp = FilaSessoes();

  /// Troca a fila do app por uma nova. Só para testes: uma operação presa
  /// num teste anterior (ex.: shared_preferences sem simulação) travaria a
  /// fila serial de todos os seguintes.
  @visibleForTesting
  static void reiniciarParaTestes() => _doApp = FilaSessoes();

  static const chave = 'fila_sessoes_v1';

  /// Acima disso, as pendentes mais antigas são descartadas (com log).
  /// Fila sem limite vira vazamento silencioso.
  final int limitePendentes;

  /// Sincronizadas ficam como histórico local; guarda só as mais recentes.
  final int limiteSincronizadas;

  /// Separadas por erro permanente; acima disso, as mais antigas saem.
  final int limiteSeparadas;

  /// Muda a cada gravação: a tela de resumo escuta para atualizar os avisos
  /// de pendência e de separadas quando o envio termina.
  final alteracoes = ValueNotifier<int>(0);

  List<SessaoLocal>? _sessoes;
  List<SessaoLocal> _separadas = [];
  Future<void> _ultima = Future.value();

  /// Executa [operacao] depois de todas as anteriores terminarem.
  Future<T> _emSerie<T>(Future<T> Function() operacao) {
    final resultado = _ultima.then((_) => operacao());
    _ultima = resultado.then((_) {}, onError: (_) {});
    return resultado;
  }

  Future<List<SessaoLocal>> _carregar() async {
    if (_sessoes != null) return _sessoes!;
    final prefs = await SharedPreferences.getInstance();
    final bruto = prefs.getString(chave);
    if (bruto == null) return _sessoes = [];
    final json = jsonDecode(bruto) as Map<String, dynamic>;
    List<SessaoLocal> lista(String k) => [
      for (final s in (json[k] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        SessaoLocal.fromJson(s),
    ];
    final sessoes = lista('sessoes');
    _separadas = lista('separadas');
    // Filas gravadas antes do espaço próprio tinham as separadas misturadas
    // às pendentes: passam para o lugar delas na leitura.
    _separadas.addAll(sessoes.where((s) => s.falha != null));
    sessoes.removeWhere((s) => s.falha != null);
    return _sessoes = sessoes;
  }

  Future<void> _gravar() async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
      chave,
      jsonEncode({
        'versao': 1,
        'sessoes': [for (final s in _sessoes!) s.toJson()],
        'separadas': [for (final s in _separadas) s.toJson()],
      }),
    );
    if (!ok) throw StateError('shared_preferences recusou a gravação da fila');
    alteracoes.value++;
  }

  /// Cópia das pendentes e sincronizadas, na ordem em que começaram. Não
  /// inclui as separadas (ver [separadas]).
  Future<List<SessaoLocal>> todas() =>
      _emSerie(() async => List.of(await _carregar()));

  /// As que aguardam envio: ainda não sincronizadas (as separadas não
  /// entram, estão fora do envio).
  Future<List<SessaoLocal>> aguardandoEnvio() => _emSerie(
    () async => [
      for (final s in await _carregar())
        if (!s.sincronizada) s,
    ],
  );

  /// As separadas por erro permanente, da mais antiga para a mais nova.
  Future<List<SessaoLocal>> separadas() => _emSerie(() async {
    await _carregar();
    return List.of(_separadas);
  });

  /// O histórico local: todas as sessões guardadas que têm lances
  /// (pendentes, sincronizadas e separadas), da mais recente para a mais
  /// antiga por `iniciada_em`. Sessão sem lance não é treino.
  Future<List<SessaoLocal>> historico() => _emSerie(() async {
    final todas = [...await _carregar(), ..._separadas]
      ..removeWhere((s) => s.lances.isEmpty)
      ..sort(
        (a, b) => DateTime.parse(b.iniciadaEm)
            .compareTo(DateTime.parse(a.iniciadaEm)),
      );
    return todas;
  });

  /// Monta, num instante só, o corpo de cada sessão aguardando envio.
  Future<List<EnvioPreparado>> prepararEnvio() => _emSerie(
    () async => [
      for (final s in await _carregar())
        if (!s.sincronizada)
          EnvioPreparado(s.uuidSessao, s._versao, s.paraEnvio()),
    ],
  );

  /// Aplica a resposta da API, sessão a sessão. Devolve as respostas das
  /// sessões removidas por terem sido rejeitadas (com o `motivo`).
  ///
  /// - `inserida`/`ja_existia`: sincronizada, com a pontuação oficial. Se a
  ///   sessão mudou depois do envio (chegou lance), continua pendente: o
  ///   servidor ainda não tem o que mudou, e o próximo envio completa.
  /// - `rejeitada`: removida (erro permanente, não adianta reenviar).
  Future<List<RespostaSessao>> aplicarRespostas(
    List<EnvioPreparado> enviados,
    List<RespostaSessao> respostas,
  ) => _emSerie(() async {
    final sessoes = await _carregar();
    final versoes = {for (final e in enviados) e.uuidSessao: e.versao};
    final rejeitadas = <RespostaSessao>[];
    for (final r in respostas) {
      final i = sessoes.indexWhere((s) => s.uuidSessao == r.uuidSessao);
      if (i < 0) continue;
      final s = sessoes[i];
      if (r.situacao == 'rejeitada') {
        sessoes.removeAt(i);
        rejeitadas.add(r);
      } else {
        s.pontuacaoServidor = r.pontuacaoTotal;
        if (versoes[s.uuidSessao] == s._versao) s.sincronizada = true;
      }
    }
    _aplicarRetencao(sessoes);
    await _gravar();
    return rejeitadas;
  });

  /// Tira a sessão do envio por erro permanente e a guarda nas separadas,
  /// que têm limite próprio e não ocupam vaga das pendentes.
  Future<void> separar(String uuidSessao, String motivo) => _emSerie(() async {
    final sessoes = await _carregar();
    final i = sessoes.indexWhere((s) => s.uuidSessao == uuidSessao);
    if (i < 0) return;
    final s = sessoes.removeAt(i)..falha = motivo;
    _separadas.add(s);
    while (_separadas.length > limiteSeparadas) {
      final antiga = _separadas.removeAt(0);
      debugPrint(
        '[FilaSessoes] limite de $limiteSeparadas separadas: descartada a '
        'sessão ${antiga.uuidSessao} (${antiga.falha}, iniciada em '
        '${antiga.iniciadaEm})',
      );
    }
    await _gravar();
  });

  /// A sessão com esse UUID (inclusive separada), ou nulo se não estiver
  /// (mais) na fila.
  Future<SessaoLocal?> sessao(String uuidSessao) => _emSerie(() async {
    for (final s in [...await _carregar(), ..._separadas]) {
      if (s.uuidSessao == uuidSessao) return s;
    }
    return null;
  });

  /// Grava a sessão nova. Só retorna depois de gravado em disco.
  Future<void> abrir(SessaoLocal sessao) => _emSerie(() async {
    final sessoes = await _carregar();
    sessoes.add(sessao);
    _aplicarLimite(sessoes, preservar: sessao.uuidSessao);
    await _gravar();
  });

  /// Acrescenta um lance e grava na hora.
  Future<void> registrarLance(String uuidSessao, LanceLocal lance) =>
      _emSerie(() async {
        final s = await _buscar(uuidSessao);
        s.lances.add(lance);
        _mudou(s);
        await _gravar();
      });

  Future<void> encerrar(String uuidSessao, DateTime encerradaEm) =>
      _emSerie(() async {
        final s = await _buscar(uuidSessao);
        s.encerradaEm = isoComFuso(encerradaEm);
        _mudou(s);
        await _gravar();
      });

  /// Algo novo para o servidor: volta a ficar pendente (uma sessão enviada
  /// no meio do treino recebe os lances seguintes no próximo envio).
  void _mudou(SessaoLocal s) {
    s._versao++;
    s.sincronizada = false;
  }

  /// Procura também nas separadas: um lance que chegue depois de a sessão
  /// ser separada é gravado nela (que segue fora do envio).
  Future<SessaoLocal> _buscar(String uuidSessao) async {
    final sessoes = await _carregar();
    return [...sessoes, ..._separadas].firstWhere(
      (s) => s.uuidSessao == uuidSessao,
      orElse: () => throw StateError('sessão $uuidSessao não está na fila'),
    );
  }

  void _aplicarLimite(List<SessaoLocal> sessoes, {required String preservar}) {
    while (true) {
      final pendentes = sessoes.where((s) => !s.sincronizada).toList();
      if (pendentes.length <= limitePendentes) return;
      final maisAntiga = pendentes.firstWhere((s) => s.uuidSessao != preservar);
      sessoes.remove(maisAntiga);
      debugPrint(
        '[FilaSessoes] limite de $limitePendentes pendentes: descartada a '
        'sessão ${maisAntiga.uuidSessao} (iniciada em ${maisAntiga.iniciadaEm}, '
        '${maisAntiga.lances.length} lances) sem sincronizar',
      );
    }
  }

  /// Guarda só as [limiteSincronizadas] sincronizadas mais recentes (pela
  /// data de início), como histórico local.
  void _aplicarRetencao(List<SessaoLocal> sessoes) {
    final sincronizadas = sessoes.where((s) => s.sincronizada).toList()
      ..sort(
        (a, b) => DateTime.parse(b.iniciadaEm)
            .compareTo(DateTime.parse(a.iniciadaEm)),
      );
    for (final antiga in sincronizadas.skip(limiteSincronizadas)) {
      sessoes.remove(antiga);
    }
  }
}
