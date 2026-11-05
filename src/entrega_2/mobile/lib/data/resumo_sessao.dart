import 'dart:math' as math;

import 'fila_sessoes.dart';
import 'pontuacao.dart';

/// Números da tela de resumo, calculados a partir dos lances gravados.
///
/// Pontuação, melhor sequência e KOs vêm da regra oficial
/// ([calcularPontuacao], a mesma do servidor). O resto é só exibição, em
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
    required this.fortes,
    required this.precisao,
    required this.mediaAngulo,
    required this.maxAngulo,
    required this.consistencia,
  });

  factory ResumoSessao.de(SessaoLocal sessao) {
    final pontuacao = calcularPontuacao(
      [
        for (final l in sessao.lances)
          LanceBruto(
            bola: l.bola,
            resultado: ResultadoLance.values.byName(l.resultado),
            anguloDecimos: decimos(l.angulo),
          ),
      ],
      dificuldadeDecimos: decimos(sessao.dificuldade),
    );

    final acertos = [
      for (final l in sessao.lances)
        if (l.resultado == 'acerto') l,
    ];
    final angulos = [for (final l in acertos) l.angulo.toDouble()];
    int classe(String c) => acertos.where((l) => l.classe == c).length;

    final total = sessao.lances.length;
    return ResumoSessao(
      pontuacaoTotal: pontuacao.pontuacaoTotal,
      melhorSequencia: pontuacao.melhorSequencia,
      kos: pontuacao.kos,
      lances: total,
      acertos: acertos.length,
      erros: total - acertos.length,
      fracos: classe('fraco'),
      medios: classe('medio'),
      fortes: classe('forte'),
      precisao: total == 0 ? null : acertos.length / total,
      mediaAngulo: angulos.isEmpty ? null : _media(angulos),
      maxAngulo: angulos.isEmpty ? null : angulos.reduce(math.max),
      consistencia: calcularConsistencia(angulos),
    );
  }

  /// Da regra oficial (iguais ao que o servidor vai calcular).
  final int pontuacaoTotal;
  final int melhorSequencia;

  /// KOs pela regra (ângulo ≥ teto), não pelo `knockout` do firmware.
  final int kos;

  final int lances;
  final int acertos;
  final int erros;

  /// Contagem pela `classe` que o firmware informou (só exibição).
  final int fracos;
  final int medios;
  final int fortes;

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
