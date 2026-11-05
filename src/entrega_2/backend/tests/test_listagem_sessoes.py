"""GET /v1/sessions (RF13): as sessoes do proprio usuario, com agregados."""

import pytest

from tests.test_sessoes import enviar, lance, sessao, versao_de
from tests.test_treinos import auth, token_admin, token_joao, token_vitoria


def listar(cliente, token, **params):
    return cliente.get("/v1/sessions", params=params, headers=auth(token))


def com_inicio(versao_id, iniciada_em, **extra):
    """Sessao de 3 lances, iniciada no instante dado (com fuso)."""
    return sessao(
        versao_id,
        lances=[lance(1), lance(2, resultado="erro"), lance(3, angulo=60.0)],
        iniciada_em=iniciada_em,
        encerrada_em=None,
        **extra,
    )


def test_lista_vazia_tem_envelope(cliente):
    token = token_vitoria(cliente)
    corpo = listar(cliente, token).json()
    assert corpo == {"items": [], "total": 0, "limit": 20, "offset": 0}


def test_exige_token(cliente):
    assert cliente.get("/v1/sessions").status_code == 401


def test_item_traz_agregados_e_nao_os_lances(cliente):
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    s = com_inicio(versao, "2026-11-05T10:00:00Z")
    enviar(cliente, token, s)

    [item] = listar(cliente, token).json()["items"]

    assert set(item) == {
        "uuid_sessao",
        "treino_titulo",
        "treino_versao",
        "iniciada_em",
        "encerrada_em",
        "pontuacao_total",
        "versao_pontuacao",
        "acertos",
        "erros",
        "kos",
        "melhor_sequencia",
        "precisao",
    }
    assert item["uuid_sessao"] == s["uuid_sessao"]
    assert item["treino_versao"] == 1
    assert item["treino_titulo"]
    assert (item["acertos"], item["erros"], item["kos"]) == (2, 1, 1)
    assert item["melhor_sequencia"] == 1
    # Em porcentagem, com 1 casa, como os totais gravam.
    assert item["precisao"] == pytest.approx(66.7)
    assert item["pontuacao_total"] > 0
    assert item["versao_pontuacao"] == 1


def test_da_mais_recente_para_a_mais_antiga(cliente):
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    # Enviadas fora de ordem, e com fusos diferentes: vale o instante.
    meio = com_inicio(versao, "2026-11-02T10:00:00Z")
    nova = com_inicio(versao, "2026-11-03T08:00:00-03:00")  # 11:00Z
    velha = com_inicio(versao, "2026-11-01T10:00:00Z")
    enviar(cliente, token, meio, nova, velha)

    uuids = [i["uuid_sessao"] for i in listar(cliente, token).json()["items"]]
    assert uuids == [nova["uuid_sessao"], meio["uuid_sessao"], velha["uuid_sessao"]]


@pytest.fixture
def tres_dias(cliente):
    """Vitoria com sessoes em 01, 02 e 03/11 as 10:00Z."""
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    s = {
        dia: com_inicio(versao, f"2026-11-0{dia}T10:00:00Z") for dia in (1, 2, 3)
    }
    enviar(cliente, token, *s.values())
    return token, {dia: x["uuid_sessao"] for dia, x in s.items()}


def uuids_de(resposta):
    return [i["uuid_sessao"] for i in resposta.json()["items"]]


def test_filtro_por_periodo_inclui_as_bordas(cliente, tres_dias):
    token, u = tres_dias

    # Bordas exatas: as duas pontas entram.
    r = listar(cliente, token, de="2026-11-02T10:00:00Z", ate="2026-11-03T10:00:00Z")
    assert uuids_de(r) == [u[3], u[2]]
    assert r.json()["total"] == 2

    # Um milissegundo para dentro: as pontas saem.
    r = listar(
        cliente, token, de="2026-11-02T10:00:00.001Z", ate="2026-11-03T09:59:59.999Z"
    )
    assert uuids_de(r) == []


def test_filtro_so_de_ou_so_ate(cliente, tres_dias):
    token, u = tres_dias
    assert uuids_de(listar(cliente, token, de="2026-11-02T10:00:00Z")) == [u[3], u[2]]
    assert uuids_de(listar(cliente, token, ate="2026-11-02T10:00:00Z")) == [u[2], u[1]]


def test_filtro_compara_instantes_em_qualquer_fuso(cliente, tres_dias):
    token, u = tres_dias
    # 07:00-03:00 e 10:00Z: o mesmo instante da sessao de 02/11.
    r = listar(cliente, token, de="2026-11-02T07:00:00-03:00", ate="2026-11-02T07:00:00-03:00")
    assert uuids_de(r) == [u[2]]


@pytest.mark.parametrize(
    "params",
    [
        {"de": "2026-11-02T10:00:00"},  # sem fuso
        {"ate": "02/11/2026"},
        {"de": "2026-11-03T00:00:00Z", "ate": "2026-11-01T00:00:00Z"},  # invertido
        {"limit": 0},
        {"limit": 101},
        {"offset": -1},
    ],
)
def test_parametros_invalidos_422(cliente, params):
    token = token_vitoria(cliente)
    assert listar(cliente, token, **params).status_code == 422


def test_paginacao(cliente):
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    s = [com_inicio(versao, f"2026-11-0{d}T10:00:00Z") for d in range(1, 6)]
    enviar(cliente, token, *s)
    esperado = [x["uuid_sessao"] for x in reversed(s)]

    p1 = listar(cliente, token, limit=2).json()
    p2 = listar(cliente, token, limit=2, offset=2).json()
    p3 = listar(cliente, token, limit=2, offset=4).json()

    assert [i["uuid_sessao"] for i in p1["items"] + p2["items"] + p3["items"]] == esperado
    assert (p1["total"], p1["limit"], p1["offset"]) == (5, 2, 0)
    assert (p3["total"], p3["offset"], len(p3["items"])) == (5, 4, 1)
    assert listar(cliente, token, offset=10).json()["items"] == []


def test_usuario_nao_ve_nem_conta_sessoes_de_outro(cliente):
    vitoria = token_vitoria(cliente)
    joao = token_joao(cliente)
    da_vitoria = com_inicio(versao_de(cliente, vitoria), "2026-11-01T10:00:00Z")
    do_joao = com_inicio(versao_de(cliente, joao), "2026-11-02T10:00:00Z")
    enviar(cliente, vitoria, da_vitoria)
    enviar(cliente, joao, do_joao)

    r_v = listar(cliente, vitoria).json()
    r_j = listar(cliente, joao).json()

    assert [i["uuid_sessao"] for i in r_v["items"]] == [da_vitoria["uuid_sessao"]]
    assert [i["uuid_sessao"] for i in r_j["items"]] == [do_joao["uuid_sessao"]]
    assert (r_v["total"], r_j["total"]) == (1, 1)


def test_dono_vem_do_token_e_parametro_nao_muda_nada(cliente):
    vitoria = token_vitoria(cliente)
    joao = token_joao(cliente)
    enviar(cliente, joao, com_inicio(versao_de(cliente, joao), "2026-11-02T10:00:00Z"))

    # Parametros desconhecidos sao ignorados: nao ha como pedir as de outro.
    r = listar(cliente, vitoria, usuario_id=2, owner_id=2, usuario="joao@tobias.dev")
    assert r.json()["total"] == 0


def test_admin_tambem_so_ve_as_proprias(cliente, promover_admin):
    joao = token_joao(cliente)
    enviar(cliente, joao, com_inicio(versao_de(cliente, joao), "2026-11-02T10:00:00Z"))
    admin = token_admin(cliente, promover_admin)

    r = listar(cliente, admin).json()
    assert (r["items"], r["total"]) == ([], 0)
