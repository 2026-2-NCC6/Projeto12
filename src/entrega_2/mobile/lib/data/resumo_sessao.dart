import 'dart:math' as math;

import 'fila_sessoes.dart';
import 'pontuacao.dart';

/// Números da tela de resumo, calculados a partir dos lances gravados.
///
/// Pontuação e melhor sequência vêm da regra oficial ([calcularPontuacao],
/// a mesma do servidor). As faixas de intensidade (fracos, médios, KO) vêm
/// do ÂNGULO, com os mesmos limiares ([faixaDoAcerto]), e nunca do campo
/// `classe` do dispositivo: fracos + médios + KO = acertos. O placar exibido é o do
/// servidor depois de sincronizada (ver [SessaoLocal.pontuacaoExibida]); a
/// sequência e os KOs, que o servidor não devolve, são sempre os locais
/// (iguais aos dele pela mesma regra). O resto é só exibição, em
/// ponto flutuante: não entra na pontuação nem precisa bater com o Python.
///
/// Campos nulos são métricas INDEFINIDAS (ex.: média sem nenhum acerto), e
/// a tela mostra "—" em vez de 0.
class ResumoSessao {
  const ResumoSessao({
    required this.pontuacaoTotal,
    required this.melhorSequencia,
    required this.kos,
    required this.lances,
    required this.acertos,
    required this.erros,
    required this.fracos,
    required this.medios,
    required this.precisao,
    required this.mediaAngulo,
    required this.maxAngulo,
    required this.consistencia,
  });

  factory ResumoSessao.de(SessaoLocal sessao) {
    final pontuacao = sessao.pontuar();

    final acertos = [
      for (final l in sessao.lances)
        if (l.resultado == 'acerto') l,
    ];
    final angulos = [for (final l in acertos) l.angulo.toDouble()];
    final dificuldade = decimos(sessao.dificuldade);
    int faixa(FaixaIntensidade f) => acertos
        .where((l) => faixaDoAcerto(decimos(l.angulo), dificuldade) == f)
        .length;

    final total = sessao.lances.length;
    return ResumoSessao(
      pontuacaoTotal: sessao.pontuacaoExibida,
      melhorSequencia: pontuacao.melhorSequencia,
      kos: faixa(FaixaIntensidade.ko),
      lances: total,
      acertos: acertos.length,
      erros: total - acertos.length,
      fracos: faixa(FaixaIntensidade.fraco),
      medios: faixa(FaixaIntensidade.medio),
      precisao: total == 0 ? null : acertos.length / total,
      mediaAngulo: angulos.isEmpty ? null : _media(angulos),
      maxAngulo: angulos.isEmpty ? null : angulos.reduce(math.max),
      consistencia: calcularConsistencia(angulos),
    );
  }

  /// O placar exibido: o oficial do servidor se sincronizada, senão o local.
  final int pontuacaoTotal;
  final int melhorSequencia;

  /// KOs pela regra (ângulo ≥ teto), não pelo `knockout` do firmware.
  final int kos;

  final int lances;
  final int acertos;
  final int erros;

  /// Faixas de intensidade dos acertos, pelo ângulo. Não há "fortes": o
  /// KO é a faixa forte.
  final int fracos;
  final int medios;

  /// De 0 a 1. Nulo sem lances.
  final double? precisao;

  /// Entre os acertos, em graus. Nulos sem acertos.
  final double? mediaAngulo;
  final double? maxAngulo;

  /// `1 − σ/μ` dos ângulos dos acertos, limitada a [0, 1] (RF12).
  /// Nula sem acertos: é indefinida, não zero.
  final double? consistencia;
}

double _media(List<double> v) => v.reduce((a, b) => a + b) / v.length;

/// `1 − (desvio padrão ÷ média)`, limitada a [0, 1].
///
/// Desvio padrão populacional: descreve ESTES lances, não estima uma
/// população (e assim um único acerto dá 1, e não uma divisão por zero).
/// Nula quando não há ângulos, ou quando a média é 0 (σ/μ indefinido).
double? calcularConsistencia(List<double> angulos) {
  if (angulos.isEmpty) return null;
  final media = _media(angulos);
  if (media <= 0) return null;
  final variancia =
      angulos.map((a) => (a - media) * (a - media)).reduce((a, b) => a + b) /
      angulos.length;
  return (1 - math.sqrt(variancia) / media).clamp(0.0, 1.0);
}

/// Comparação com a sessão anterior (RF12): a diferença de pontuação entre
/// [atual] e a sessão imediatamente anterior a ela, ou nulo se não houver.
///
/// "Anterior" é a mais recente que começou antes de [atual] (por
/// `iniciada_em`), com lances, sincronizada ou não. Compara a
/// [SessaoLocal.pontuacaoExibida] das duas: o número oficial do servidor
/// sempre que existir.
///
/// O histórico é o local (até 10 sincronizadas + pendentes): uma sessão
/// anterior que já saiu da fila não é encontrada, e aí não há comparação.
int? variacaoSobreAnterior(SessaoLocal atual, Iterable<SessaoLocal> guardadas) {
  final inicio = DateTime.parse(atual.iniciadaEm);
  SessaoLocal? anterior;
  DateTime? inicioAnterior;
  for (final s in guardadas) {
    if (s.uuidSessao == atual.uuidSessao || s.lances.isEmpty) continue;
    final i = DateTime.parse(s.iniciadaEm);
    if (!i.isBefore(inicio)) continue;
    if (inicioAnterior == null || i.isAfter(inicioAnterior)) {
      anterior = s;
      inicioAnterior = i;
    }
  }
  return anterior == null
      ? null
      : atual.pontuacaoExibida - anterior.pontuacaoExibida;
}
