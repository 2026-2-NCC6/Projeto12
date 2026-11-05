/// Dashboard do histórico: agregados das sessões que o SERVIDOR conhece
/// (`GET /v1/sessions`), sem o teto de dez sessões da fila local.
///
/// Tudo aqui é função pura, para os testes: o "agora" e a conversão para o
/// fuso local entram por parâmetro.
library;

/// Uma sessão como `GET /v1/sessions` devolve (só agregados, sem lances).
class SessaoApi {
  const SessaoApi({
    required this.uuidSessao,
    required this.treinoTitulo,
    required this.treinoVersao,
    required this.iniciadaEm,
    required this.encerradaEm,
    required this.pontuacaoTotal,
    required this.acertos,
    required this.erros,
    required this.kos,
    required this.melhorSequencia,
    required this.precisao,
  });

  factory SessaoApi.fromJson(Map<String, dynamic> j) => SessaoApi(
    uuidSessao: j['uuid_sessao'] as String,
    treinoTitulo: j['treino_titulo'] as String,
    treinoVersao: j['treino_versao'] as int,
    iniciadaEm: DateTime.parse(j['iniciada_em'] as String).toUtc(),
    encerradaEm: switch (j['encerrada_em']) {
      final String s => DateTime.parse(s).toUtc(),
      _ => null,
    },
    pontuacaoTotal: j['pontuacao_total'] as int?,
    acertos: j['acertos'] as int,
    erros: j['erros'] as int,
    kos: j['kos'] as int,
    melhorSequencia: j['melhor_sequencia'] as int,
    precisao: (j['precisao'] as num?)?.toDouble(),
  );

  final String uuidSessao;
  final String treinoTitulo;
  final int treinoVersao;

  /// Em UTC, como a API devolve. Converta para o fuso do aparelho ANTES de
  /// agrupar por dia ([frequenciaSemanal]).
  final DateTime iniciadaEm;
  final DateTime? encerradaEm;

  /// Nula se o servidor ainda não pontuou a sessão.
  final int? pontuacaoTotal;
  final int acertos;
  final int erros;

  /// Subconjunto de [acertos]: todo KO é um acerto.
  final int kos;
  final int melhorSequencia;

  /// Em PORCENTAGEM com uma casa (66.7), não de 0 a 1. Só informativa: o
  /// Dashboard agrega por [acertos] e [erros], nunca pela média disto.
  final double? precisao;
}

/// Os chips do Dashboard.
enum PeriodoDashboard {
  seteDias(7, '7 dias'),
  trintaDias(30, '30 dias'),
  tudo(null, 'Tudo');

  const PeriodoDashboard(this.dias, this.rotulo);

  /// Nulo em "Tudo": sem limite, e sem período anterior.
  final int? dias;
  final String rotulo;
}

/// Uma janela de tempo, as duas pontas inclusivas (como `de`/`ate` da API).
class Janela {
  const Janela(this.de, this.ate);
  final DateTime de;
  final DateTime ate;
}

/// A janela do período e a imediatamente anterior, do mesmo tamanho.
///
/// Em dias LOCAIS: "7 dias" vai da meia-noite de 6 dias atrás até agora
/// (hoje e os 6 dias anteriores). A anterior termina 1 ms antes de a atual
/// começar, para nenhuma sessão contar nas duas. "Tudo" não tem janela.
(Janela, Janela)? janelas(PeriodoDashboard periodo, DateTime agoraLocal) {
  final dias = periodo.dias;
  if (dias == null) return null;
  final hoje = DateTime(agoraLocal.year, agoraLocal.month, agoraLocal.day);
  // DateTime(..., dia − n) e não subtract(Duration): atravessa horário de
  // verão sem errar a meia-noite.
  final inicio = DateTime(hoje.year, hoje.month, hoje.day - (dias - 1));
  final inicioAnterior = DateTime(inicio.year, inicio.month, inicio.day - dias);
  return (
    Janela(inicio, agoraLocal),
    Janela(inicioAnterior, inicio.subtract(const Duration(milliseconds: 1))),
  );
}

/// Os três segmentos da distribuição dos lances. DISJUNTOS: o KO é
/// destacado de dentro dos acertos, e não somado ao lado deles (somar
/// acertos + KO + erros contaria o KO duas vezes).
class Distribuicao {
  const Distribuicao({
    required this.acertosSemKo,
    required this.kos,
    required this.erros,
  });

  final int acertosSemKo;
  final int kos;
  final int erros;

  int get acertos => acertosSemKo + kos;
  int get total => acertosSemKo + kos + erros;

  /// Porcentagens inteiras que SOMAM 100 (maiores restos), na ordem
  /// acertos sem KO, KO, erros. Nulo sem lances.
  (int, int, int)? get porcentagens {
    if (total == 0) return null;
    final partes = [acertosSemKo, kos, erros];
    final exatos = [for (final p in partes) p * 100 / total];
    final inteiros = [for (final e in exatos) e.floor()];
    var falta = 100 - inteiros.fold(0, (a, b) => a + b);
    final ordem = [0, 1, 2]
      ..sort((a, b) => (exatos[b] - inteiros[b]).compareTo(exatos[a] - inteiros[a]));
    for (final i in ordem) {
      if (falta == 0) break;
      inteiros[i]++;
      falta--;
    }
    return (inteiros[0], inteiros[1], inteiros[2]);
  }
}

/// Os números de um período.
class AgregadoPeriodo {
  const AgregadoPeriodo({
    required this.sessoes,
    required this.pontuacaoTotal,
    required this.precisao,
    required this.melhorSequencia,
    required this.distribuicao,
  });

  /// Em ordem cronológica (a mais antiga primeiro), para o gráfico.
  final List<SessaoApi> sessoes;
  final int pontuacaoTotal;

  /// De 0 a 1: soma(acertos) / soma(acertos + erros), PONDERADA por
  /// lances. Nunca a média das precisões das sessões (uma de 3 lances
  /// pesaria igual a uma de 30). Nula sem lances.
  final double? precisao;
  final int melhorSequencia;
  final Distribuicao distribuicao;

  bool get vazio => sessoes.isEmpty;
}

AgregadoPeriodo agregar(Iterable<SessaoApi> sessoes) {
  final lista = sessoes.toList()
    ..sort((a, b) => a.iniciadaEm.compareTo(b.iniciadaEm));
  var pontos = 0, acertos = 0, erros = 0, kos = 0, melhor = 0;
  for (final s in lista) {
    pontos += s.pontuacaoTotal ?? 0;
    acertos += s.acertos;
    erros += s.erros;
    kos += s.kos;
    if (s.melhorSequencia > melhor) melhor = s.melhorSequencia;
  }
  final lances = acertos + erros;
  return AgregadoPeriodo(
    sessoes: List.unmodifiable(lista),
    pontuacaoTotal: pontos,
    precisao: lances == 0 ? null : acertos / lances,
    melhorSequencia: melhor,
    distribuicao: Distribuicao(
      acertosSemKo: acertos - kos,
      kos: kos,
      erros: erros,
    ),
  );
}

/// Variação percentual da pontuação contra o período anterior. Nula quando
/// não há período anterior ("Tudo") ou ele não tem pontos (base zero).
int? variacaoPontuacao(AgregadoPeriodo atual, AgregadoPeriodo? anterior) {
  if (anterior == null || anterior.pontuacaoTotal == 0) return null;
  return ((atual.pontuacaoTotal - anterior.pontuacaoTotal) *
          100 /
          anterior.pontuacaoTotal)
      .round();
}

/// Variação da precisão em PONTOS PERCENTUAIS (84% → 90% = +6 pts), não em
/// porcentagem de porcentagem. Nula sem período anterior ou sem lances.
int? variacaoPrecisaoPts(AgregadoPeriodo atual, AgregadoPeriodo? anterior) {
  final a = atual.precisao, b = anterior?.precisao;
  if (a == null || b == null) return null;
  return ((a - b) * 100).round();
}

/// Os últimos 7 dias LOCAIS (o mais antigo primeiro, hoje por último): o
/// dia e se houve pelo menos uma sessão nele.
///
/// [paraLocal] converte o `iniciada_em` (UTC) para o fuso do aparelho
/// ANTES de agrupar: uma sessão às 22h em São Paulo é 01h do dia seguinte
/// em UTC, e agrupar pelo valor cru a jogaria no dia errado.
List<(DateTime, bool)> frequenciaSemanal(
  Iterable<SessaoApi> sessoes,
  DateTime agoraLocal, {
  DateTime Function(DateTime utc)? paraLocal,
}) {
  final local = paraLocal ?? (DateTime d) => d.toLocal();
  String chave(DateTime d) => '${d.year}-${d.month}-${d.day}';
  final treinados = {for (final s in sessoes) chave(local(s.iniciadaEm))};
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final dia = DateTime(agoraLocal.year, agoraLocal.month, agoraLocal.day - i);
        return (dia, treinados.contains(chave(dia)));
      }(),
  ];
}
