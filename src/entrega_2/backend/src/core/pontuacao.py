"""Regra de pontuacao do TOBIAS, versao 1 (US-705).

Modulo puro: sem banco, sem datetime, sem aleatoriedade. A mesma regra
precisa existir identica em Dart (US-606); o contrato entre os dois lados
sao os golden fixtures em `contracts/pontuacao/golden.json`.

Divergencia em relacao a secao 6.2 do documento do projeto
-----------------------------------------------------------
A formula original usa a_pk (pico de aceleracao em g), a_ref (mediana da
calibracao em g), Omega (integral do giroscopio em 2 s) e t_r (tempo entre
o cue e o impacto). O firmware entregue nao produz nenhum dos quatro: mede
angulo de inclinacao em graus, nunca le o giroscopio (lerAcelerometroRaw le
6 bytes a partir de 0x3B, so acelerometro) e nao emite cue. A formula foi
escrita para o firmware planejado, nao para o construido.

Esta versao preserva o raciocinio de design - curva concava, multiplicador
de sequencia com teto, bonus de KO, penalidade por erro - nas grandezas que
existem. Pontos de reacao ficam de fora: sem cue, estimar por ts_ms daria um
numero sem significado fisico. Se o cue existir, o termo volta na versao 2.

Principio: so medidas brutas
----------------------------
A pontuacao usa apenas `resultado` e `angulo`, mais a `dificuldade` da
sessao. `classe` e `knockout` sao interpretacoes do firmware (servem para
escolher o MP3) e sao ignoradas; o KO e recalculado aqui pela mesma regra
do firmware (pico >= ANGULO_KO + calibracao).

Aritmetica (obrigatoria para a equivalencia com o Dart)
-------------------------------------------------------
- so inteiros: angulos e dificuldade entram em decimos de grau;
- nenhuma divisao com operando negativo (`//` do Python arredonda para
  baixo, `~/` do Dart trunca para zero: so coincidem sem negativos);
- nenhum round().
"""

from dataclasses import dataclass
from decimal import Decimal

VERSAO_REGRA = 1

PISO = 220  # 22,0 graus: ANGULO_GATILHO do firmware (nao se move com a calibracao)
TETO_BASE = 580  # 58,0 graus: ANGULO_KO do firmware, deslocado pela calibracao
ESCALA = 1000  # I vai de 0 a 1000

BONUS_KO = 75
PENALIDADE_ERRO = -20
TETO_SEQUENCIA = 10  # Nao alterar: a secao 5.4 depende dele para o AFD bastar.

ACERTO = "acerto"
ERRO = "erro"


@dataclass(frozen=True)
class LanceBruto:
    bola: int
    resultado: str  # "acerto" | "erro"
    angulo_decimos: int


@dataclass(frozen=True)
class ResultadoPontuacao:
    """Tudo na ordem de `bola` crescente."""

    pontos_por_lance: tuple[int, ...]
    ko_por_lance: tuple[bool, ...]
    pontuacao_total: int
    melhor_sequencia: int
    kos: int


def decimos(valor) -> int:
    """Converte graus (Decimal, int ou str) em decimos, de forma exata.

    Recusa float de proposito: a conversao tem de ser exata por
    construcao. Recusa mais de uma casa decimal: o contrato so aceita uma.
    """
    if isinstance(valor, float):
        raise TypeError("use Decimal, nao float, para angulos e dificuldade")
    escalado = Decimal(valor) * 10
    if escalado != escalado.to_integral_value():
        raise ValueError(f"{valor} tem mais de uma casa decimal")
    return int(escalado)


def teto_da_sessao(dificuldade_decimos: int) -> int:
    return TETO_BASE + dificuldade_decimos


def intensidade(angulo_decimos: int, teto: int) -> int:
    """I = clamp((angulo - piso) * 1000 // (teto - piso), 0, 1000).

    O max(0, ...) vem ANTES da divisao: abaixo do piso o numerador seria
    negativo, e ai Python e Dart divergem.
    """
    acima_do_piso = max(0, angulo_decimos - PISO)
    return min(acima_do_piso * ESCALA // (teto - PISO), ESCALA)


def pontos_forca(i: int) -> int:
    """De 10 a 100. Tres segmentos de inclinacao decrescente no lugar do
    expoente 0,7 da secao 6.2: mesma concavidade, aritmetica exata."""
    if i <= 400:
        f = (50 * i) // 400
    elif i <= 700:
        f = 50 + (22 * (i - 400)) // 300
    else:
        f = 72 + (18 * (i - 700)) // 300
    return 10 + f


def multiplicador(sequencia_anterior: int) -> int:
    """Em porcentagem, de 100 a 200."""
    return 100 + 10 * min(sequencia_anterior, TETO_SEQUENCIA)


def calcular(lances, dificuldade_decimos: int) -> ResultadoPontuacao:
    """Pontua uma sessao inteira.

    Os lances sao ordenados por `bola` (ordenacao estavel: empates mantem
    a ordem de entrada). A sequencia e a de acertos consecutivos nessa
    ordem; erro zera.
    """
    if dificuldade_decimos < 0:
        raise ValueError("dificuldade nao pode ser negativa")
    teto = teto_da_sessao(dificuldade_decimos)

    pontos, kos_por_lance = [], []
    sequencia = melhor = 0

    for lance in sorted(lances, key=lambda l: l.bola):
        if lance.resultado == ACERTO:
            ko = lance.angulo_decimos >= teto
            base = pontos_forca(intensidade(lance.angulo_decimos, teto))
            pontos.append(base * multiplicador(sequencia) // 100 + (BONUS_KO if ko else 0))
            kos_por_lance.append(ko)
            sequencia += 1
            melhor = max(melhor, sequencia)
        elif lance.resultado == ERRO:
            pontos.append(PENALIDADE_ERRO)
            kos_por_lance.append(False)
            sequencia = 0
        else:
            raise ValueError(f"resultado desconhecido: {lance.resultado!r}")

    return ResultadoPontuacao(
        pontos_por_lance=tuple(pontos),
        ko_por_lance=tuple(kos_por_lance),
        pontuacao_total=max(0, sum(pontos)),
        melhor_sequencia=melhor,
        kos=sum(kos_por_lance),
    )
