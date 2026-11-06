/// Ranking (`GET /v1/ranking`): modelo da resposta e textos de cada métrica.
library;

import 'format.dart';

/// As três métricas do ranking. "Consistência", que está no Figma, foi
/// descartada e não existe na API.
enum MetricaRanking {
  pontos(
    rotulo: 'Pontos',
    // O período escrito aqui é o que a API usa de verdade: período errado na
    // tela é pior que período nenhum.
    subtitulo: 'Soma de pontos nos últimos 30 dias.',
    semNinguem: 'Ninguém pontuou nos últimos 30 dias.',
  ),
  frequencia(
    rotulo: 'Frequência',
    subtitulo: 'Quem mais treinou nos últimos 7 dias.',
    semNinguem: 'Ninguém treinou nos últimos 7 dias.',
  ),
  evolucao(
    rotulo: 'Evolução',
    subtitulo:
        'Quem mais evoluiu, comparando os últimos 30 dias com os 30 anteriores.',
    semNinguem:
        'Ninguém tem sessões suficientes nos dois períodos para comparar.',
  );

  const MetricaRanking({
    required this.rotulo,
    required this.subtitulo,
    required this.semNinguem,
  });

  final String rotulo;
  final String subtitulo;

  /// Estado vazio: a lista pública não tem ninguém no período.
  final String semNinguem;

  /// Valor do parâmetro `metrica` da API.
  String get api => name;
}

/// Uma linha do ranking. Só apelido: a API não manda nome, e-mail nem id.
class ItemRanking {
  const ItemRanking({
    required this.posicao,
    required this.apelido,
    required this.valor,
    required this.sessoes,
    this.oculto = false,
  });

  factory ItemRanking.fromJson(Map<String, dynamic> json) => ItemRanking(
    posicao: json['posicao'] as int,
    apelido: json['apelido'] as String,
    valor: json['valor'] as num,
    sessoes: json['sessoes'] as int,
    // Só vem no `voce`. Ausente vira `false`: o texto neutro (`Sua posição`)
    // nunca afirma nada falso; o de oculto, sim, se não for o caso.
    oculto: json['oculto'] as bool? ?? false,
  );

  final int posicao;
  final String apelido;

  /// Inteiro em pontos e frequência; percentual (1 casa) em evolução.
  final num valor;
  final int sessoes;

  /// Só no `voce`: fora da lista pública POR REGRA de privacidade (menor de
  /// idade, sem data de nascimento). Falso para quem só está abaixo do corte
  /// dos 20: esse está no ranking e pode subir treinando.
  final bool oculto;

  String get inicial => apelido.isEmpty ? '?' : apelido[0].toUpperCase();
}

class RespostaRanking {
  const RespostaRanking({
    required this.metrica,
    required this.itens,
    required this.voce,
  });

  factory RespostaRanking.fromJson(Map<String, dynamic> json) =>
      RespostaRanking(
        metrica: MetricaRanking.values.byName(json['metrica'] as String),
        itens: [
          for (final i in json['itens'] as List)
            ItemRanking.fromJson(i as Map<String, dynamic>),
        ],
        voce: json['voce'] == null
            ? null
            : ItemRanking.fromJson(json['voce'] as Map<String, dynamic>),
      );

  final MetricaRanking metrica;

  /// Os 20 primeiros da lista pública (adultos), em ordem.
  final List<ItemRanking> itens;

  /// Quem está usando o app. Nulo sem sessão no período (na evolução,
  /// também abaixo do mínimo de sessões).
  final ItemRanking? voce;

  /// `voce` está na lista? Comparado pelo apelido, que é único. Fora dela,
  /// ou está abaixo dos 20, ou está oculto por regra ([ItemRanking.oculto]);
  /// neste caso, a posição pode COINCIDIR com a de alguém visível.
  bool get voceNaLista =>
      voce != null && itens.any((i) => i.apelido == voce!.apelido);
}

/// Valor no formato da métrica: "2.538", "6 dias", "+288%".
///
/// Evolução negativa leva o sinal e nada mais: treinar menos não pede alerta.
String fmtValorRanking(MetricaRanking metrica, num valor) => switch (metrica) {
  MetricaRanking.pontos => fmtInt(valor.round()),
  MetricaRanking.frequencia => valor.round() == 1 ? '1 dia' : '${valor.round()} dias',
  MetricaRanking.evolucao => _fmtPercentual(valor),
};

String _fmtPercentual(num valor) {
  final inteiro = valor.round();
  if (inteiro == 0) return '0%';
  return inteiro > 0 ? '+$inteiro%' : '−${-inteiro}%';
}
