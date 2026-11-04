import logging
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import pytest
from sqlalchemy.exc import IntegrityError

from src.models.log_auditoria import LogAuditoria
from src.models.sessao import Lance, Sessao
from src.routers import sessoes as rota_sessoes
from tests.test_treinos import (
    auth,
    criar_treino,
    token_admin,
    token_joao,
    token_vitoria,
)


def versao_de(cliente, token):
    """Cria um treino e devolve o id da versao atual dele."""
    return criar_treino(cliente, token).json()["versao_atual"]["id"]


def lance(bola, resultado="acerto", classe="forte", knockout=False, angulo=55.0):
    if resultado == "erro":
        classe, knockout, angulo = "sem_impacto", False, 0.0
    return {
        "uuid_lance": str(uuid.uuid4()),
        "id_lance_firmware": f"L-{1000 * bola}-{bola}",
        "bola": bola,
        "resultado": resultado,
        "classe": classe,
        "knockout": knockout,
        "angulo": angulo,
        "ts_ms": 1000 * bola,
    }


# 15 acertos de 55,0 graus (I=916, 94 pontos de forca), sequencia 0..14
# com teto em 10: 94,103,112,122,131,141,150,159,169,178 e 188 x 5.
PONTOS_15_LANCES_55_GRAUS = 2299


def sessao(versao_id, lances=None, **extra):
    corpo = {
        "uuid_sessao": str(uuid.uuid4()),
        "treino_versao_id": versao_id,
        "iniciada_em": "2026-11-04T19:30:00-03:00",
        "encerrada_em": "2026-11-04T19:34:12-03:00",
        "lances": lances if lances is not None else [lance(n) for n in range(1, 16)],
    }
    corpo.update(extra)
    return corpo


def enviar(cliente, token, *sessoes_):
    return cliente.post(
        "/v1/sessions", json={"sessoes": list(sessoes_)}, headers=auth(token)
    )


# Fabrica de sessoes do banco de teste. Vem da fixture `abrir_db`: importar
# o conftest criaria um segundo banco em memoria (ver promover_admin).
SessionTeste = None


@pytest.fixture(autouse=True)
def _banco_de_teste(abrir_db):
    global SessionTeste
    SessionTeste = abrir_db


def contar(modelo):
    db = SessionTeste()
    try:
        return db.query(modelo).count()
    finally:
        db.close()


def sessao_no_banco(uuid_sessao):
    db = SessionTeste()
    try:
        return db.query(Sessao).filter(Sessao.uuid_sessao == uuid.UUID(uuid_sessao)).all()
    finally:
        db.close()


# --- Aceite: lote novo ------------------------------------------------------


def test_lote_novo_insere_tudo(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token))

    resposta = enviar(cliente, token, s)

    assert resposta.status_code == 200
    assert resposta.json() == {
        "sessoes": [
            {
                "uuid_sessao": s["uuid_sessao"],
                "situacao": "inserida",
                "motivo": None,
                "lances_recebidos": 15,
                "lances_inseridos": 15,
                "lances_duplicados": 0,
                "pontuacao_total": PONTOS_15_LANCES_55_GRAUS,
            }
        ]
    }
    assert contar(Sessao) == 1
    assert contar(Lance) == 15


def test_lote_com_varias_sessoes(cliente):
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)

    corpo = enviar(cliente, token, sessao(versao), sessao(versao, lances=[])).json()

    assert [r["situacao"] for r in corpo["sessoes"]] == ["inserida", "inserida"]
    assert contar(Sessao) == 2
    assert contar(Lance) == 15


def test_guarda_id_do_firmware_e_versao(cliente):
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    s = sessao(versao)

    enviar(cliente, token, s)

    [gravada] = sessao_no_banco(s["uuid_sessao"])
    assert gravada.treino_versao_id == versao
    db = SessionTeste()
    ids = {l.id_lance_firmware for l in db.query(Lance).all()}
    db.close()
    assert ids == {l["id_lance_firmware"] for l in s["lances"]}


# --- Aceite: reenvio nao duplica -------------------------------------------


def test_reenvio_identico_nao_duplica(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token))
    enviar(cliente, token, s)

    resposta = enviar(cliente, token, s)

    assert resposta.status_code == 200
    [resumo] = resposta.json()["sessoes"]
    assert resumo["situacao"] == "ja_existia"
    assert resumo["lances_inseridos"] == 0
    assert resumo["lances_duplicados"] == 15
    assert contar(Sessao) == 1
    assert contar(Lance) == 15


def test_uuid_de_lance_repetido_no_proprio_payload(cliente):
    token = token_vitoria(cliente)
    repetido = lance(1)
    s = sessao(versao_de(cliente, token), lances=[repetido, dict(repetido)])

    [resumo] = enviar(cliente, token, s).json()["sessoes"]

    assert resumo["lances_inseridos"] == 1
    assert resumo["lances_duplicados"] == 1
    assert contar(Lance) == 1


def test_primeira_gravacao_vence_nos_campos_imutaveis(cliente):
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    outra_versao = versao_de(cliente, token)
    s = sessao(versao)
    enviar(cliente, token, s)

    alterada = dict(s, treino_versao_id=outra_versao, iniciada_em="2026-11-05T10:00:00Z")
    enviar(cliente, token, alterada)

    [gravada] = sessao_no_banco(s["uuid_sessao"])
    assert gravada.treino_versao_id == versao


# --- Aceite: lote parcialmente novo ----------------------------------------


def test_lote_parcial_insere_so_sessoes_novas(cliente):
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    antiga = sessao(versao)
    enviar(cliente, token, antiga)

    nova = sessao(versao)
    corpo = enviar(cliente, token, antiga, nova).json()

    assert [r["situacao"] for r in corpo["sessoes"]] == ["ja_existia", "inserida"]
    assert contar(Sessao) == 2
    assert contar(Lance) == 30


def test_sessao_existente_recebe_lances_que_faltavam(cliente):
    """Sincronizou no lance 8, caiu a rede, reenviou os 15."""
    token = token_vitoria(cliente)
    completa = sessao(versao_de(cliente, token))
    parcial = dict(completa, lances=completa["lances"][:8], encerrada_em=None)
    enviar(cliente, token, parcial)

    [resumo] = enviar(cliente, token, completa).json()["sessoes"]

    assert resumo["situacao"] == "ja_existia"
    assert resumo["lances_inseridos"] == 7
    assert resumo["lances_duplicados"] == 8
    assert contar(Lance) == 15
    [gravada] = sessao_no_banco(completa["uuid_sessao"])
    assert gravada.encerrada_em is not None
    assert gravada.acertos == 15


def test_encerrada_em_nao_e_sobrescrita(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token))
    enviar(cliente, token, s)
    original = sessao_no_banco(s["uuid_sessao"])[0].encerrada_em

    enviar(cliente, token, dict(s, encerrada_em="2026-11-04T23:59:00-03:00"))

    assert sessao_no_banco(s["uuid_sessao"])[0].encerrada_em == original


# --- Fidelidade: grava exatamente o que foi enviado ------------------------


def instante(valor):
    """Instante em UTC de uma data lida do banco ou do payload.

    O SQLite devolve sem fuso (ja em UTC, porque o schema normaliza);
    o Postgres devolve com fuso. Os dois viram o mesmo objeto aqui.
    """
    if isinstance(valor, str):
        valor = datetime.fromisoformat(valor)
    if valor.tzinfo is None:
        return valor.replace(tzinfo=timezone.utc)
    return valor.astimezone(timezone.utc)


def test_datas_no_passado_sao_gravadas_exatamente(cliente):
    """Treinou em 1/10 e sincronizou hoje: a sessao fica datada de 1/10.

    A data e longe de now() de proposito, para nao passar por coincidencia.
    """
    token = token_vitoria(cliente)
    s = sessao(
        versao_de(cliente, token),
        iniciada_em="2026-10-01T08:15:00-03:00",
        encerrada_em="2026-10-01T08:19:30-03:00",
    )

    enviar(cliente, token, s)

    [g] = sessao_no_banco(s["uuid_sessao"])
    assert instante(g.iniciada_em) == datetime(2026, 10, 1, 11, 15, tzinfo=timezone.utc)
    assert instante(g.encerrada_em) == datetime(2026, 10, 1, 11, 19, 30, tzinfo=timezone.utc)
    # recebida_em e a hora do servidor, e deve continuar sendo.
    assert instante(g.recebida_em) - instante(g.encerrada_em) > timedelta(days=1)


def test_encerrada_em_preenchida_depois_e_a_enviada(cliente):
    """O merge da sessao aberta tambem grava a data do payload, nao now()."""
    token = token_vitoria(cliente)
    s = sessao(
        versao_de(cliente, token),
        iniciada_em="2026-10-01T08:15:00-03:00",
        encerrada_em="2026-10-01T08:19:30-03:00",
    )
    enviar(cliente, token, dict(s, lances=s["lances"][:8], encerrada_em=None))
    assert sessao_no_banco(s["uuid_sessao"])[0].encerrada_em is None

    enviar(cliente, token, s)

    [g] = sessao_no_banco(s["uuid_sessao"])
    assert instante(g.encerrada_em) == instante(s["encerrada_em"])
    assert instante(g.iniciada_em) == instante(s["iniciada_em"])


def test_fuso_diferente_preserva_o_instante_e_nao_o_relogio(cliente):
    """13:15+02:00 e 08:15-03:00 sao o mesmo instante (11:15Z)."""
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    europa = sessao(
        versao,
        iniciada_em="2026-10-01T13:15:00+02:00",
        encerrada_em="2026-10-01T13:19:30+02:00",
    )
    brasil = sessao(
        versao,
        iniciada_em="2026-10-01T08:15:00-03:00",
        encerrada_em="2026-10-01T08:19:30-03:00",
    )

    enviar(cliente, token, europa, brasil)

    [ge] = sessao_no_banco(europa["uuid_sessao"])
    [gb] = sessao_no_banco(brasil["uuid_sessao"])
    esperado = datetime(2026, 10, 1, 11, 15, tzinfo=timezone.utc)
    assert instante(ge.iniciada_em) == esperado
    assert instante(gb.iniciada_em) == esperado
    assert instante(ge.encerrada_em) == instante(gb.encerrada_em)


def test_lances_gravam_cada_campo_sem_transformacao(cliente, abrir_db):
    token = token_vitoria(cliente)
    enviados = [
        {
            "uuid_lance": str(uuid.uuid4()),
            "id_lance_firmware": "L-98765-7",
            "bola": 7,
            "resultado": "acerto",
            "classe": "fraco",
            "knockout": False,
            "angulo": 17.3,
            "ts_ms": 123456789,
        },
        {
            "uuid_lance": str(uuid.uuid4()),
            "id_lance_firmware": "L-4321-2",
            "bola": 2,
            "resultado": "acerto",
            "classe": "forte",
            "knockout": True,
            "angulo": 61.4,
            "ts_ms": 4321,
        },
        {
            "uuid_lance": str(uuid.uuid4()),
            "id_lance_firmware": "L-9000-3",
            "bola": 3,
            "resultado": "erro",
            "classe": "sem_impacto",
            "knockout": False,
            "angulo": 0.0,
            "ts_ms": 9000,
        },
        {
            "uuid_lance": str(uuid.uuid4()),
            "id_lance_firmware": None,
            "bola": 4,
            "resultado": "acerto",
            "classe": "medio",
            "knockout": False,
            "angulo": 179.9,
            "ts_ms": 0,
        },
    ]
    enviar(cliente, token, sessao(versao_de(cliente, token), lances=enviados))

    db = abrir_db()
    gravados = {str(l.uuid_lance): l for l in db.query(Lance).all()}
    db.close()

    assert set(gravados) == {e["uuid_lance"] for e in enviados}
    for e in enviados:
        g = gravados[e["uuid_lance"]]
        assert {
            "uuid_lance": str(g.uuid_lance),
            "id_lance_firmware": g.id_lance_firmware,
            "bola": g.bola,
            "resultado": g.resultado.value,
            "classe": g.classe.value,
            "knockout": g.knockout,
            "angulo": g.angulo,
            "ts_ms": g.ts_ms,
        } == dict(e, angulo=Decimal(str(e["angulo"])))


# --- Totais recalculados ----------------------------------------------------


def test_totais_recalculados_a_partir_dos_lances(cliente):
    token = token_vitoria(cliente)
    lances = [
        lance(1, angulo=40.0),
        lance(2, angulo=70.0, knockout=True),
        lance(3, resultado="erro"),
        lance(4, angulo=20.0, classe="fraco"),
        lance(5, angulo=50.0),
        lance(6, angulo=60.0, knockout=True),
    ]
    s = sessao(versao_de(cliente, token), lances=lances)
    # Agregados mentirosos do cliente: ignorados, nao viram 422.
    s.update({"acertos": 99, "erros": 0, "kos": 50, "precisao": 100, "pontuacao_total": 9999})

    assert enviar(cliente, token, s).status_code == 200

    [g] = sessao_no_banco(s["uuid_sessao"])
    assert g.acertos == 5
    assert g.erros == 1
    assert g.kos == 2
    assert g.melhor_sequencia == 3
    assert g.media_angulo == 48.0
    assert g.max_angulo == 70.0
    assert g.precisao == pytest.approx(83.3)
    # 67 + 185 - 20 + 10 + 94 + 195, e nao os 9999 do cliente.
    assert g.pontuacao_total == 531


def test_sessao_sem_lances_tem_totais_vazios(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), lances=[])

    enviar(cliente, token, s)

    [g] = sessao_no_banco(s["uuid_sessao"])
    assert (g.acertos, g.erros, g.kos, g.melhor_sequencia) == (0, 0, 0, 0)
    assert g.media_angulo is None and g.max_angulo is None and g.precisao is None


# --- Aceite: payload malformado -> 422 -------------------------------------


def _lance_com(**campos):
    base = lance(1)
    base.update(campos)
    return base


@pytest.mark.parametrize(
    "mexer",
    [
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(classe="ko")), id="classe-invalida"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(angulo=181)), id="angulo-acima"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(angulo=-1)), id="angulo-negativo"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(uuid_lance="L-1000-1")), id="uuid-lance-malformado"),
        pytest.param(lambda s: s.__setitem__("uuid_sessao", "nao-e-uuid"), id="uuid-sessao-malformado"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(resultado="talvez")), id="resultado-invalido"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(bola=0)), id="bola-zero"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(ts_ms=-5)), id="ts-negativo"),
        pytest.param(lambda s: s.__setitem__("iniciada_em", "2026-11-04T19:30:00"), id="data-sem-fuso"),
        pytest.param(lambda s: s.__setitem__("encerrada_em", "2026-11-04T19:34:12"), id="encerrada-sem-fuso"),
        pytest.param(lambda s: s.__setitem__("encerrada_em", "2026-11-04T19:00:00-03:00"), id="encerrada-antes-de-iniciada"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(resultado="erro", classe="sem_impacto", angulo=12.5)), id="erro-com-angulo"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(resultado="erro", classe="forte", angulo=0)), id="erro-com-classe"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(resultado="erro", classe="sem_impacto", angulo=0, knockout=True)), id="erro-com-ko"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(classe="sem_impacto")), id="acerto-sem-impacto"),
        pytest.param(lambda s: s.pop("treino_versao_id"), id="sem-versao"),
        pytest.param(lambda s: s.__setitem__("lances", [lance(1)] * 501), id="lances-acima-do-limite"),
        pytest.param(lambda s: s["lances"].__setitem__(0, _lance_com(angulo=61.45)), id="angulo-duas-casas"),
        pytest.param(lambda s: s.__setitem__("dificuldade", 2.25), id="dificuldade-duas-casas"),
        pytest.param(lambda s: s.__setitem__("dificuldade", 45.1), id="dificuldade-acima"),
        pytest.param(lambda s: s.__setitem__("dificuldade", -1), id="dificuldade-negativa"),
        pytest.param(lambda s: s.__setitem__("pontuacao_cliente", -5), id="placar-negativo"),
        pytest.param(lambda s: s.__setitem__("pontuacao_cliente", 10.5), id="placar-fracionario"),
    ],
)
def test_sessao_malformada_rejeita_lote_com_422(cliente, mexer):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token))
    mexer(s)

    resposta = enviar(cliente, token, s)

    assert resposta.status_code == 422
    assert contar(Sessao) == 0


def test_lote_vazio_422(cliente):
    token = token_vitoria(cliente)
    assert enviar(cliente, token).status_code == 422


def test_lote_acima_do_limite_422(cliente):
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    resposta = enviar(cliente, token, *[sessao(versao, lances=[]) for _ in range(51)])
    assert resposta.status_code == 422
    assert contar(Sessao) == 0


def test_uma_sessao_malformada_derruba_o_lote_todo(cliente):
    """422 e validacao de schema: acontece antes de tocar no banco."""
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    ruim = sessao(versao)
    ruim["lances"][0]["angulo"] = 500

    assert enviar(cliente, token, sessao(versao), ruim).status_code == 422
    assert contar(Sessao) == 0


def test_erro_no_formato_do_firmware_e_aceito(cliente):
    """O JSON que registrarErroTimeout() emite passa na regra de coerencia."""
    token = token_vitoria(cliente)
    erro = {
        "uuid_lance": str(uuid.uuid4()),
        "id_lance_firmware": "L-9000-3",
        "bola": 3,
        "resultado": "erro",
        "classe": "sem_impacto",
        "knockout": False,
        "angulo": 0.0,
        "ts_ms": 9000,
    }
    s = sessao(versao_de(cliente, token), lances=[erro])
    assert enviar(cliente, token, s).status_code == 200


# --- Autenticacao e acesso a versao ----------------------------------------


def test_exige_token(cliente):
    resposta = cliente.post("/v1/sessions", json={"sessoes": [sessao(1)]})
    assert resposta.status_code == 401


def test_versao_de_outro_dono_e_rejeitada_sem_revelar(cliente):
    token_v = token_vitoria(cliente)
    versao_da_vitoria = versao_de(cliente, token_v)
    token_j = token_joao(cliente)

    resposta = enviar(cliente, token_j, sessao(versao_da_vitoria))

    assert resposta.status_code == 200
    [resumo] = resposta.json()["sessoes"]
    assert resumo["situacao"] == "rejeitada"
    assert resumo["motivo"] == "versao_invalida"
    assert resumo["lances_inseridos"] == 0
    assert contar(Sessao) == 0


def test_versao_inexistente_tem_mesmo_motivo_que_versao_alheia(cliente):
    token_v = token_vitoria(cliente)
    alheia = versao_de(cliente, token_v)
    token_j = token_joao(cliente)

    r_alheia = enviar(cliente, token_j, sessao(alheia)).json()["sessoes"][0]
    r_inexistente = enviar(cliente, token_j, sessao(99999)).json()["sessoes"][0]

    for chave in ("situacao", "motivo", "lances_inseridos", "lances_duplicados"):
        assert r_alheia[chave] == r_inexistente[chave]


def test_sessao_rejeitada_nao_derruba_as_outras(cliente):
    token_v = token_vitoria(cliente)
    alheia = versao_de(cliente, token_v)
    token_j = token_joao(cliente)
    propria = versao_de(cliente, token_j)

    corpo = enviar(cliente, token_j, sessao(alheia), sessao(propria)).json()

    assert [r["situacao"] for r in corpo["sessoes"]] == ["rejeitada", "inserida"]
    assert contar(Sessao) == 1


def test_versao_do_catalogo_e_aceita(cliente, promover_admin):
    admin = token_admin(cliente, promover_admin)
    versao_catalogo = versao_de(cliente, admin)
    token_j = token_joao(cliente)

    [resumo] = enviar(cliente, token_j, sessao(versao_catalogo)).json()["sessoes"]

    assert resumo["situacao"] == "inserida"


def test_treino_apagado_ainda_recebe_sessao(cliente):
    """Treinou offline, o treino foi apagado, sincronizou depois."""
    token = token_vitoria(cliente)
    treino = criar_treino(cliente, token).json()
    cliente.delete(f"/v1/drills/{treino['id']}", headers=auth(token))

    s = sessao(treino["versao_atual"]["id"])
    [resumo] = enviar(cliente, token, s).json()["sessoes"]

    assert resumo["situacao"] == "inserida"


def test_versao_antiga_continua_valendo(cliente):
    """Treinou na versao 1; o treino foi editado antes da sincronizacao."""
    token = token_vitoria(cliente)
    treino = criar_treino(cliente, token).json()
    v1 = treino["versao_atual"]["id"]
    v2 = cliente.put(
        f"/v1/drills/{treino['id']}",
        json={"titulo": "Editado", "nivel": "dificil", "qtd_lances": 10, "intervalo_ms": 4000},
        headers=auth(token),
    ).json()["versao_atual"]["id"]
    assert v1 != v2

    s = sessao(v1)
    enviar(cliente, token, s)

    assert sessao_no_banco(s["uuid_sessao"])[0].treino_versao_id == v1


# --- Seguranca: espacos de UUID por usuario --------------------------------


def test_mesmo_uuid_sessao_em_dois_usuarios_nao_colide(cliente):
    token_v = token_vitoria(cliente)
    versao_v = versao_de(cliente, token_v)
    token_j = token_joao(cliente)
    versao_j = versao_de(cliente, token_j)

    s_v = sessao(versao_v)
    s_j = sessao(
        versao_j,
        uuid_sessao=s_v["uuid_sessao"],
        lances=[dict(l) for l in s_v["lances"]],  # ate os uuid_lance iguais
    )

    r_v = enviar(cliente, token_v, s_v).json()["sessoes"][0]
    r_j = enviar(cliente, token_j, s_j).json()["sessoes"][0]

    # O Joao nao ve nenhum sinal de que o UUID ja existia para a Vitoria.
    assert r_j == r_v
    assert r_j["situacao"] == "inserida"
    assert r_j["lances_duplicados"] == 0

    gravadas = sessao_no_banco(s_v["uuid_sessao"])
    assert len(gravadas) == 2
    assert {g.usuario_id for g in gravadas} == {1, 2}
    assert {g.treino_versao_id for g in gravadas} == {versao_v, versao_j}
    assert contar(Lance) == 30


def test_dono_vem_do_token_e_nao_do_corpo(cliente):
    token_v = token_vitoria(cliente)
    token_j = token_joao(cliente)
    versao_j = versao_de(cliente, token_j)

    s = sessao(versao_j, usuario_id=1)
    enviar(cliente, token_j, s)

    [gravada] = sessao_no_banco(s["uuid_sessao"])
    assert gravada.usuario_id == 2


# --- Concorrencia -----------------------------------------------------------


def test_integrity_error_desfaz_so_a_sessao_e_tenta_de_novo(cliente, monkeypatch):
    """Simula o indice unico barrando uma gravacao concorrente."""
    token = token_vitoria(cliente)
    versao = versao_de(cliente, token)
    original = rota_sessoes.ingerir_sessao
    chamadas = []

    def falha_na_primeira(db, usuario, dados, versoes_ok, ip):
        chamadas.append(dados.uuid_sessao)
        resumo = original(db, usuario, dados, versoes_ok, ip)
        if len(chamadas) == 1:
            raise IntegrityError("INSERT", {}, Exception("unique violation"))
        return resumo

    monkeypatch.setattr(rota_sessoes, "ingerir_sessao", falha_na_primeira)

    outra = sessao(versao)
    resposta = enviar(cliente, token, sessao(versao), outra)

    assert resposta.status_code == 200
    assert len(chamadas) == 3  # 1a sessao duas vezes, 2a uma vez
    # "inserida" na 2a tentativa prova que o savepoint desfez a 1a: sem o
    # rollback, a sessao ja estaria la e o resultado seria "ja_existia".
    assert [r["situacao"] for r in resposta.json()["sessoes"]] == ["inserida", "inserida"]
    assert contar(LogAuditoria) == 2
    assert contar(Sessao) == 2
    assert contar(Lance) == 30


# --- Auditoria e contrato do treino ----------------------------------------


def test_ingestao_registra_auditoria(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token))

    enviar(cliente, token, s)
    enviar(cliente, token, s)  # reenvio puro: nada mudou, nada a auditar

    db = SessionTeste()
    registros = db.query(LogAuditoria).all()
    db.close()
    [gravada] = sessao_no_banco(s["uuid_sessao"])
    assert [(r.acao, r.entidade, r.entidade_id, r.usuario_id) for r in registros] == [
        ("sessao_inserida", "sessao", str(gravada.id), 1)
    ]


def test_versao_saida_expoe_id(cliente):
    token = token_vitoria(cliente)
    treino = criar_treino(cliente, token).json()

    assert isinstance(treino["versao_atual"]["id"], int)
    versoes = cliente.get(f"/v1/drills/{treino['id']}/versions", headers=auth(token)).json()
    assert versoes[0]["id"] == treino["versao_atual"]["id"]


# --- Pontuacao autoritativa (US-705) ---------------------------------------


def alertas(caplog):
    return [
        r for r in caplog.records
        if r.name == "tobias.pontuacao" and r.levelno == logging.WARNING
    ]


def auditorias(acao):
    db = SessionTeste()
    try:
        return db.query(LogAuditoria).filter(LogAuditoria.acao == acao).all()
    finally:
        db.close()


def lances_no_banco(uuid_sessao):
    db = SessionTeste()
    try:
        [s] = db.query(Sessao).filter(Sessao.uuid_sessao == uuid.UUID(uuid_sessao)).all()
        return db.query(Lance).filter(Lance.sessao_id == s.id).order_by(Lance.bola).all()
    finally:
        db.close()


def test_sessao_nova_e_pontuada(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token))

    [resumo] = enviar(cliente, token, s).json()["sessoes"]

    assert resumo["pontuacao_total"] == PONTOS_15_LANCES_55_GRAUS
    [g] = sessao_no_banco(s["uuid_sessao"])
    assert g.pontuacao_total == PONTOS_15_LANCES_55_GRAUS
    assert g.versao_pontuacao == 1
    assert [l.pontos for l in lances_no_banco(s["uuid_sessao"])] == [
        94, 103, 112, 122, 131, 141, 150, 159, 169, 178, 188, 188, 188, 188, 188
    ]


def test_dificuldade_e_gravada_e_usada(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), lances=[lance(1, angulo=60.0)], dificuldade=10.0)

    [resumo] = enviar(cliente, token, s).json()["sessoes"]

    # Com 10 graus de dificuldade o teto vai a 68,0: 60,0 nao e KO e vale 89.
    assert resumo["pontuacao_total"] == 89
    [g] = sessao_no_banco(s["uuid_sessao"])
    assert g.dificuldade == Decimal("10.0")
    assert g.kos == 0


def test_dificuldade_padrao_e_zero(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), lances=[lance(1, angulo=60.0)])

    [resumo] = enviar(cliente, token, s).json()["sessoes"]

    assert resumo["pontuacao_total"] == 175
    assert sessao_no_banco(s["uuid_sessao"])[0].dificuldade == 0


def test_ko_vem_do_angulo_e_ignora_knockout_e_classe_do_cliente(cliente):
    token = token_vitoria(cliente)
    # Os flags somam 2 KOs; o angulo da 1. Os dois numeros precisam
    # diferir, senao o teste nao distingue "calculado" de "lido".
    mentiroso_1 = lance(1, angulo=25.0, classe="forte", knockout=True)
    mentiroso_2 = lance(2, angulo=30.0, classe="forte", knockout=True)
    modesto = lance(3, angulo=60.0, classe="fraco", knockout=False)
    s = sessao(versao_de(cliente, token), lances=[mentiroso_1, mentiroso_2, modesto])

    [resumo] = enviar(cliente, token, s).json()["sessoes"]

    # 25,0: 20 sem KO; 30,0: 37 x 110% = 40 sem KO; 60,0: 100 x 120% + 75.
    assert [l.pontos for l in lances_no_banco(s["uuid_sessao"])] == [20, 40, 195]
    assert resumo["pontuacao_total"] == 255
    assert sessao_no_banco(s["uuid_sessao"])[0].kos == 1
    # Os campos interpretados continuam guardados como vieram.
    assert [l.knockout for l in lances_no_banco(s["uuid_sessao"])] == [True, True, False]


def test_merge_recalcula_a_sessao_inteira(cliente):
    """Lances 9-15 chegam depois: a sequencia continua, nao recomeca."""
    token = token_vitoria(cliente)
    completa = sessao(versao_de(cliente, token))
    enviar(cliente, token, dict(completa, lances=completa["lances"][:8], encerrada_em=None))
    parcial = sessao_no_banco(completa["uuid_sessao"])[0].pontuacao_total
    assert parcial == 94 + 103 + 112 + 122 + 131 + 141 + 150 + 159

    [resumo] = enviar(cliente, token, completa).json()["sessoes"]

    assert resumo["pontuacao_total"] == PONTOS_15_LANCES_55_GRAUS
    # O lance 9 entra com sequencia 8 (180%), nao com sequencia 0 (100%):
    # somar so os lances novos daria 94 aqui.
    assert lances_no_banco(completa["uuid_sessao"])[8].pontos == 169


def test_placar_mentiroso_do_cliente_e_ignorado(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), pontuacao_cliente=999_999)

    [resumo] = enviar(cliente, token, s).json()["sessoes"]

    assert resumo["pontuacao_total"] == PONTOS_15_LANCES_55_GRAUS
    assert sessao_no_banco(s["uuid_sessao"])[0].pontuacao_total == PONTOS_15_LANCES_55_GRAUS


def test_divergencia_dispara_alerta_e_auditoria(cliente, caplog):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), pontuacao_cliente=3000)

    with caplog.at_level(logging.WARNING, logger="tobias.pontuacao"):
        enviar(cliente, token, s)

    [g] = sessao_no_banco(s["uuid_sessao"])
    [alerta] = alertas(caplog)
    assert alerta.evento == "pontuacao_divergente"
    assert alerta.sessao_id == str(g.id)
    assert alerta.usuario_id == 1
    assert alerta.pontuacao_servidor == PONTOS_15_LANCES_55_GRAUS
    assert alerta.pontuacao_cliente == 3000
    assert alerta.versao_regra == 1
    # Sem dados pessoais na mensagem.
    assert "vitoria" not in alerta.getMessage().lower()

    [registro] = auditorias("pontuacao_divergente")
    assert (registro.entidade, registro.entidade_id, registro.usuario_id) == (
        "sessao", str(g.id), 1
    )


def test_sem_alerta_quando_placares_batem(cliente, caplog):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), pontuacao_cliente=PONTOS_15_LANCES_55_GRAUS)

    with caplog.at_level(logging.WARNING, logger="tobias.pontuacao"):
        enviar(cliente, token, s)

    assert alertas(caplog) == []
    assert auditorias("pontuacao_divergente") == []


def test_sem_alerta_quando_app_nao_manda_placar(cliente, caplog):
    token = token_vitoria(cliente)

    with caplog.at_level(logging.WARNING, logger="tobias.pontuacao"):
        enviar(cliente, token, sessao(versao_de(cliente, token)))

    assert alertas(caplog) == []
    assert auditorias("pontuacao_divergente") == []


def test_sem_alerta_em_sincronizacao_parcial(cliente, caplog):
    """O app manda so os lances novos (9-15) com um placar: o servidor tem
    1-15, o app pontuou 7. A comparacao nao faria sentido."""
    token = token_vitoria(cliente)
    completa = sessao(versao_de(cliente, token))
    enviar(cliente, token, dict(completa, lances=completa["lances"][:8], encerrada_em=None))

    so_novos = dict(completa, lances=completa["lances"][8:], pontuacao_cliente=1)
    with caplog.at_level(logging.WARNING, logger="tobias.pontuacao"):
        [resumo] = enviar(cliente, token, so_novos).json()["sessoes"]

    assert resumo["lances_inseridos"] == 7  # a requisicao mudou algo...
    assert alertas(caplog) == []  # ...mas nao cobre os lances gravados
    assert auditorias("pontuacao_divergente") == []


def test_reenvio_identico_nao_repete_o_alerta(cliente, caplog):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), pontuacao_cliente=3000)

    with caplog.at_level(logging.WARNING, logger="tobias.pontuacao"):
        enviar(cliente, token, s)
        enviar(cliente, token, s)
        enviar(cliente, token, s)

    assert len(alertas(caplog)) == 1
    assert len(auditorias("pontuacao_divergente")) == 1


def test_sessao_rejeitada_nao_tem_pontuacao(cliente):
    token_v = token_vitoria(cliente)
    alheia = versao_de(cliente, token_v)
    token_j = token_joao(cliente)

    [resumo] = enviar(cliente, token_j, sessao(alheia)).json()["sessoes"]

    assert resumo["situacao"] == "rejeitada"
    assert resumo["pontuacao_total"] is None


def test_comando_pontua_sessoes_antigas(cliente):
    """Sessoes gravadas antes da US-705 tem pontuacao nula."""
    from src.scripts.recalcular_pontuacao import recalcular_pendentes

    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token))
    enviar(cliente, token, s)

    db = SessionTeste()
    [antiga] = db.query(Sessao).all()
    antiga.pontuacao_total = None
    antiga.versao_pontuacao = None
    for l in db.query(Lance).all():
        l.pontos = 0
    db.commit()

    assert recalcular_pendentes(db) == 1
    assert recalcular_pendentes(db) == 0  # idempotente
    db.close()

    [g] = sessao_no_banco(s["uuid_sessao"])
    assert g.pontuacao_total == PONTOS_15_LANCES_55_GRAUS
    assert g.versao_pontuacao == 1
    assert lances_no_banco(s["uuid_sessao"])[-1].pontos == 188
