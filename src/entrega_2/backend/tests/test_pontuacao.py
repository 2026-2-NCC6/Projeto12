"""Regra de pontuacao pura (src/core/pontuacao.py), sem banco nem API."""

import json
from decimal import Decimal
from pathlib import Path

import pytest

from src.core import pontuacao

GOLDEN = json.loads(
    (Path(__file__).parent.parent / "contracts" / "pontuacao" / "golden.json").read_text(
        encoding="utf-8"
    ),
    # Decimal direto do texto do JSON, como a API faz: nada de float.
    parse_float=Decimal,
)


def lances_do_caso(caso):
    return [
        pontuacao.LanceBruto(
            bola=l["bola"],
            resultado=l["resultado"],
            angulo_decimos=pontuacao.decimos(l["angulo"]),
        )
        for l in caso["lances"]
    ]


def test_fixtures_sao_da_versao_atual_da_regra():
    assert GOLDEN["versao_regra"] == pontuacao.VERSAO_REGRA


def test_fixtures_nao_trazem_campos_interpretados():
    """classe e knockout nao entram na regra; nao podem estar na entrada."""
    for caso in GOLDEN["casos"]:
        for lance in caso["lances"]:
            assert set(lance) == {"bola", "resultado", "angulo"}, caso["id"]


@pytest.mark.parametrize("caso", GOLDEN["casos"], ids=lambda c: c["id"])
def test_golden(caso):
    r = pontuacao.calcular(lances_do_caso(caso), pontuacao.decimos(caso["dificuldade"]))

    assert {
        "pontos_por_lance": list(r.pontos_por_lance),
        "pontuacao_total": r.pontuacao_total,
        "melhor_sequencia": r.melhor_sequencia,
        "kos": r.kos,
    } == caso["esperado"]


@pytest.mark.parametrize("dificuldade", [0, 1, 55, 100, 125, 450])
def test_ko_se_e_somente_se_intensidade_satura(dificuldade):
    """ko e verdadeiro exatamente quando I == 1000: os dois saturam juntos."""
    teto = pontuacao.teto_da_sessao(dificuldade)
    for angulo_decimos in range(0, 1801):
        i = pontuacao.intensidade(angulo_decimos, teto)
        r = pontuacao.calcular([pontuacao.LanceBruto(1, "acerto", angulo_decimos)], dificuldade)
        assert r.ko_por_lance[0] == (i == 1000), (angulo_decimos, dificuldade)


def test_ko_usa_maior_ou_igual_no_limiar():
    r = pontuacao.calcular(
        [
            pontuacao.LanceBruto(1, "acerto", 579),
            pontuacao.LanceBruto(2, "erro", 0),
            pontuacao.LanceBruto(3, "acerto", 580),
        ],
        0,
    )
    assert r.ko_por_lance == (False, False, True)


def test_pontos_de_forca_vao_de_10_a_100_sem_descer():
    anteriores = [pontuacao.pontos_forca(i) for i in range(0, 1001)]
    assert anteriores[0] == 10 and anteriores[-1] == 100
    assert all(a <= b for a, b in zip(anteriores, anteriores[1:]))


def test_multiplicador_tem_teto_em_10():
    assert [pontuacao.multiplicador(s) for s in (0, 1, 10, 11, 500)] == [100, 110, 200, 200, 200]


def test_nenhuma_divisao_recebe_negativo_abaixo_do_piso():
    """Abaixo do piso o numerador e zerado antes da divisao."""
    assert pontuacao.intensidade(0, 580) == 0
    assert pontuacao.intensidade(219, 580) == 0


@pytest.mark.parametrize(
    "valor, esperado",
    [(Decimal("61.4"), 614), (Decimal("25"), 250), ("0.1", 1), (0, 0), (Decimal("180.0"), 1800)],
)
def test_decimos_e_exato(valor, esperado):
    assert pontuacao.decimos(valor) == esperado


def test_decimos_recusa_float():
    with pytest.raises(TypeError):
        pontuacao.decimos(61.4)


def test_decimos_recusa_mais_de_uma_casa():
    with pytest.raises(ValueError):
        pontuacao.decimos(Decimal("61.45"))


def test_resultado_desconhecido_e_erro_de_programacao():
    with pytest.raises(ValueError):
        pontuacao.calcular([pontuacao.LanceBruto(1, "ko", 600)], 0)
