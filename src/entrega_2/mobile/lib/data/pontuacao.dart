/// Regra de pontuação do TOBIAS, versão 1 — espelho exato de
/// `backend/src/core/pontuacao.py`.
///
/// Especificação: `backend/contracts/spec-pontuacao-v1.md`. O contrato entre
/// as duas implementações são os golden fixtures em
/// `backend/contracts/pontuacao/golden.json`, lidos pelos testes dos dois
/// lados. Mudou a fórmula aqui? Mude no Python, nos fixtures e suba a
/// versão da regra.
///
/// Função pura: sem `DateTime.now()`, sem aleatoriedade, sem I/O.
///
/// Aritmética (obrigatória para bater com o Python):
/// - só `int`: ângulos e dificuldade entram em décimos de grau;
/// - divisão só com `~/` e nunca com operando negativo (o `//` do Python
///   arredonda para baixo, o `~/` trunca para zero: só coincidem sem
///   negativos) — por isso o limite em zero vem ANTES da divisão;
/// - `round()` só na fronteira de entrada ([decimos]); na fórmula, nenhum.
///
/// Os valores ficam abaixo de 2 milhões, então também são exatos no Flutter
/// Web, onde `int` é um número do JavaScript.
library;

/// Versão da regra; tem de ser igual a `versao_regra` dos fixtures e a
/// `VERSAO_REGRA` do backend.
const versaoRegraPontuacao = 1;

/// 22,0° — ANGULO_GATILHO do firmware (não se move com a calibração).
const piso = 220;

/// 58,0° — ANGULO_KO do firmware, deslocado pela dificuldade da sessão.
const tetoBase = 580;

const _escala = 1000;
const bonusKo = 75;
const penalidadeErro = -20;

/// Não alterar: a seção 5.4 do documento da equipe depende deste teto
/// para que um AFD baste (entrega de Teoria da Computação).
const tetoSequencia = 10;

enum ResultadoLance { acerto, erro }

/// Só as medidas brutas. `classe` e `knockout` do firmware ficam de fora
/// de propósito: são interpretações, e o KO é recalculado pelo ângulo.
class LanceBruto {
  const LanceBruto({
    required this.bola,
    required this.resultado,
    required this.anguloDecimos,
  });

  final int bola;
  final ResultadoLance resultado;

  /// Ângulo em décimos de grau (61,4° → 614). Use [decimos] para converter.
  final int anguloDecimos;
}

/// Tudo na ordem de `bola` crescente.
class ResultadoPontuacao {
  const ResultadoPontuacao({
    required this.pontosPorLance,
    required this.koPorLance,
    required this.pontuacaoTotal,
    required this.melhorSequencia,
    required this.kos,
  });

  final List<int> pontosPorLance;
  final List<bool> koPorLance;
  final int pontuacaoTotal;
  final int melhorSequencia;
  final int kos;
}

/// Converte graus em décimos de grau. É o ÚNICO `round()` da regra.
///
/// Exato para valores com até uma casa decimal (o contrato não aceita mais
/// que isso; o firmware envia `String(x, 1)`). Com mais casas, lança
/// [ArgumentError], como o `decimos` do Python.
int decimos(num graus) {
  final escalado = graus * 10;
  final inteiro = escalado.round();
  if ((escalado - inteiro).abs() > 1e-6) {
    throw ArgumentError.value(graus, 'graus', 'mais de uma casa decimal');
  }
  return inteiro;
}

int tetoDaSessao(int dificuldadeDecimos) => tetoBase + dificuldadeDecimos;

/// I = min(1000, max(0, angulo − piso) · 1000 ~/ (teto − piso)).
int intensidade(int anguloDecimos, int teto) {
  final acimaDoPiso = anguloDecimos - piso < 0 ? 0 : anguloDecimos - piso;
  final i = acimaDoPiso * _escala ~/ (teto - piso);
  return i > _escala ? _escala : i;
}

/// De 10 a 100: três segmentos de inclinação decrescente (curva côncava).
int pontosForca(int i) {
  final int f;
  if (i <= 400) {
    f = (50 * i) ~/ 400;
  } else if (i <= 700) {
    f = 50 + (22 * (i - 400)) ~/ 300;
  } else {
    f = 72 + (18 * (i - 700)) ~/ 300;
  }
  return 10 + f;
}

/// Em porcentagem, de 100 a 200.
int multiplicador(int sequenciaAnterior) =>
    100 +
    10 * (sequenciaAnterior < tetoSequencia ? sequenciaAnterior : tetoSequencia);

/// Pontua uma sessão inteira.
///
/// Os lances são ordenados por `bola`, e empates mantêm a ordem de entrada,
/// como o `sorted` do Python. O `List.sort` do Dart NÃO garante isso, por
/// isso o desempate explícito pelo índice original.
ResultadoPontuacao calcularPontuacao(
  List<LanceBruto> lances, {
  required int dificuldadeDecimos,
}) {
  if (dificuldadeDecimos < 0) {
    throw ArgumentError.value(
      dificuldadeDecimos,
      'dificuldadeDecimos',
      'não pode ser negativa',
    );
  }
  final teto = tetoDaSessao(dificuldadeDecimos);

  final indices = List<int>.generate(lances.length, (i) => i)
    ..sort((a, b) {
      final porBola = lances[a].bola.compareTo(lances[b].bola);
      return porBola != 0 ? porBola : a.compareTo(b);
    });

  final pontos = <int>[];
  final kos = <bool>[];
  var sequencia = 0;
  var melhor = 0;

  for (final indice in indices) {
    final lance = lances[indice];
    switch (lance.resultado) {
      case ResultadoLance.acerto:
        final ko = lance.anguloDecimos >= teto;
        final base = pontosForca(intensidade(lance.anguloDecimos, teto));
        pontos.add(base * multiplicador(sequencia) ~/ 100 + (ko ? bonusKo : 0));
        kos.add(ko);
        sequencia += 1;
        if (sequencia > melhor) melhor = sequencia;
      case ResultadoLance.erro:
        pontos.add(penalidadeErro);
        kos.add(false);
        sequencia = 0;
    }
  }

  final soma = pontos.fold(0, (a, b) => a + b);
  return ResultadoPontuacao(
    pontosPorLance: List.unmodifiable(pontos),
    koPorLance: List.unmodifiable(kos),
    pontuacaoTotal: soma < 0 ? 0 : soma,
    melhorSequencia: melhor,
    kos: kos.where((k) => k).length,
  );
}
