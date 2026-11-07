"""Perfil: calibrado_em, edicao do apelido e exclusao da conta."""

from datetime import datetime, timezone

import pytest

from src.models.log_auditoria import LogAuditoria
from src.models.sessao import Lance, Sessao
from src.models.treino import Escopo, Treino, TreinoVersao
from src.models.usuario import Usuario
from tests.test_auth import cadastrar, logar
from tests.test_sessoes import enviar, lance, sessao
from tests.test_treinos import CORPO, auth, criar_treino, token_admin, token_joao, token_vitoria

SENHA = "senha12345"  # a de cadastrar()


def eu(cliente, token):
    return cliente.get("/v1/auth/eu", headers=auth(token))


def calibrar(cliente, token, valor):
    return cliente.put("/v1/auth/calibracao", json={"calibracao": valor}, headers=auth(token))


def patch(cliente, token, corpo):
    return cliente.patch("/v1/auth/eu", json=corpo, headers=auth(token))


def excluir(cliente, token, corpo):
    return cliente.request("DELETE", "/v1/auth/eu", json=corpo, headers=auth(token))


@pytest.fixture
def db(abrir_db):
    sessao_db = abrir_db()
    yield sessao_db
    sessao_db.close()


def contar(db, modelo, *condicoes):
    db.expire_all()
    return db.query(modelo).filter(*condicoes).count()


# --- calibrado_em -------------------------------------------------------------


def test_eu_traz_calibracao_e_calibrado_em_nulo_antes_de_calibrar(cliente):
    token = token_vitoria(cliente)
    corpo = eu(cliente, token).json()
    assert corpo["calibracao"] == 0.0
    assert corpo["calibrado_em"] is None


def test_calibrar_marca_calibrado_em(cliente):
    token = token_vitoria(cliente)
    r = calibrar(cliente, token, 7.5)
    assert r.status_code == 200
    assert r.json()["calibracao"] == 7.5
    assert r.json()["calibrado_em"] is not None
    assert eu(cliente, token).json()["calibrado_em"] == r.json()["calibrado_em"]


def test_calibracao_zero_legitima_fica_marcada(cliente):
    """O caso que motiva o campo: mediana de 38 graus ou menos da calibracao 0,
    igual a quem nunca calibrou. So calibrado_em diferencia os dois."""
    nunca = token_joao(cliente)
    calibrou = token_vitoria(cliente)
    calibrar(cliente, calibrou, 0)

    de_quem_calibrou = eu(cliente, calibrou).json()
    de_quem_nunca = eu(cliente, nunca).json()

    assert de_quem_calibrou["calibracao"] == de_quem_nunca["calibracao"] == 0.0
    assert de_quem_calibrou["calibrado_em"] is not None
    assert de_quem_nunca["calibrado_em"] is None


def test_recalibrar_atualiza_a_marca(cliente):
    token = token_vitoria(cliente)
    primeira = datetime.fromisoformat(calibrar(cliente, token, 3).json()["calibrado_em"])
    segunda = datetime.fromisoformat(calibrar(cliente, token, 0).json()["calibrado_em"])
    assert segunda >= primeira


# --- Editar apelido -----------------------------------------------------------


def test_troca_o_apelido(cliente):
    token = token_vitoria(cliente)
    r = patch(cliente, token, {"apelido": "VickAce"})
    assert r.status_code == 200
    assert r.json()["apelido"] == "VickAce"
    assert eu(cliente, token).json()["apelido"] == "VickAce"


def test_apelido_duplicado_da_o_mesmo_erro_do_cadastro(cliente):
    token_joao(cliente)  # apelido "Joao"
    vitoria = token_vitoria(cliente)

    no_cadastro = cadastrar(cliente, email="outra@tobias.dev", apelido="Joao")
    na_edicao = patch(cliente, vitoria, {"apelido": "Joao"})

    assert na_edicao.status_code == no_cadastro.status_code == 409
    assert na_edicao.json() == no_cadastro.json()
    assert eu(cliente, vitoria).json()["apelido"] == "Vick"


def test_manter_o_proprio_apelido_nao_e_conflito(cliente):
    token = token_vitoria(cliente)
    assert patch(cliente, token, {"apelido": "Vick"}).status_code == 200


@pytest.mark.parametrize("apelido", ["V", "x" * 41, ""])
def test_apelido_invalido_e_recusado_como_no_cadastro(cliente, apelido):
    token = token_vitoria(cliente)
    assert patch(cliente, token, {"apelido": apelido}).status_code == 422
    assert cadastrar(cliente, email="nova@tobias.dev", apelido=apelido).status_code == 422


@pytest.mark.parametrize(
    "corpo",
    [
        {"apelido": "Novo", "email": "outro@tobias.dev"},
        {"apelido": "Novo", "nome": "Outro Nome"},
        {"apelido": "Novo", "id": 2},
        {"email": "outro@tobias.dev"},
        {},
    ],
)
def test_so_o_apelido_e_editavel(cliente, corpo):
    token = token_vitoria(cliente)
    antes = eu(cliente, token).json()
    assert patch(cliente, token, corpo).status_code == 422
    assert eu(cliente, token).json() == antes


def test_patch_exige_token(cliente):
    assert cliente.patch("/v1/auth/eu", json={"apelido": "X1"}).status_code == 401


# --- Excluir conta: recusas ---------------------------------------------------


def test_exclusao_sem_senha_e_recusada(cliente):
    token = token_vitoria(cliente)
    assert excluir(cliente, token, {}).status_code == 422
    assert cliente.request("DELETE", "/v1/auth/eu", headers=auth(token)).status_code == 422
    assert eu(cliente, token).status_code == 200


def test_exclusao_com_senha_errada_da_o_mesmo_erro_do_login(cliente):
    token = token_vitoria(cliente)
    r = excluir(cliente, token, {"senha": "senha-errada"})
    login_errado = cliente.post(
        "/v1/auth/login", json={"email": "vitoria@tobias.dev", "senha": "senha-errada"}
    )
    assert r.status_code == login_errado.status_code == 401
    assert r.json() == login_errado.json()
    assert eu(cliente, token).status_code == 200


def test_exclusao_exige_token(cliente):
    r = cliente.request("DELETE", "/v1/auth/eu", json={"senha": SENHA})
    assert r.status_code == 401


def virar_catalogo(db, treino_id, apagado=False):
    """Pela API o catalogo nasce sem dono (owner_id nulo). Um catalogo COM
    dono surge pelo painel admin, que deixa mudar o escopo de um treino
    pessoal."""
    t = db.get(Treino, treino_id)
    t.escopo = Escopo.catalogo
    if apagado:
        t.apagado_em = datetime.now(timezone.utc)
    db.commit()


def orfaos_na_auditoria(db):
    db.expire_all()
    return sorted(
        int(r.entidade_id)
        for r in db.query(LogAuditoria).filter(LogAuditoria.acao == "treino_orfanado")
    )


@pytest.mark.parametrize("apagado", [False, True], ids=["ativo", "apagado_logicamente"])
def test_dono_de_treino_do_catalogo_exclui_e_o_treino_fica_sem_dono(cliente, db, apagado):
    joao = token_joao(cliente)
    vitoria = token_vitoria(cliente)
    jid = eu(cliente, joao).json()["id"]
    vid = eu(cliente, vitoria).json()["id"]
    treino = criar_treino(cliente, joao).json()
    versao = treino["versao_atual"]["id"]
    virar_catalogo(db, treino["id"])
    # Do catalogo: a Vitoria tambem treina nele.
    enviar(cliente, joao, sessao(versao))
    s_vitoria = sessao(versao)
    assert enviar(cliente, vitoria, s_vitoria).json()["sessoes"][0]["situacao"] == "inserida"
    # Apagado logicamente tambem fica: o historico ainda aponta para ele.
    if apagado:
        virar_catalogo(db, treino["id"], apagado=True)

    r = excluir(cliente, joao, {"senha": SENHA})

    assert r.status_code == 204
    assert eu(cliente, joao).status_code == 401
    # O treino fica, sem dono, com a versao.
    db.expire_all()
    sobrevivente = db.get(Treino, treino["id"])
    assert sobrevivente is not None
    assert sobrevivente.owner_id is None
    assert sobrevivente.escopo == Escopo.catalogo
    assert contar(db, TreinoVersao, TreinoVersao.id == versao) == 1
    # As sessoes do Joao vao embora; a da Vitoria fica, com os lances.
    assert contar(db, Sessao, Sessao.usuario_id == jid) == 0
    [dela] = db.query(Sessao).filter(Sessao.usuario_id == vid).all()
    assert str(dela.uuid_sessao) == s_vitoria["uuid_sessao"]
    assert contar(db, Lance, Lance.sessao_id == dela.id) == 15
    assert orfaos_na_auditoria(db) == [treino["id"]]


def test_admin_que_publicou_no_catalogo_exclui_e_o_catalogo_fica(cliente, promover_admin, db):
    """O catalogo criado pela API nao tem dono: excluir quem o publicou nao
    pode leva-lo junto."""
    admin = token_admin(cliente, promover_admin)
    treino = criar_treino(cliente, admin).json()
    assert treino["escopo"] == "catalogo"

    assert excluir(cliente, admin, {"senha": SENHA}).status_code == 204

    assert contar(db, Treino, Treino.id == treino["id"]) == 1
    assert contar(db, TreinoVersao, TreinoVersao.treino_id == treino["id"]) == 1


def test_treino_pessoal_com_sessao_de_outro_fica_sem_dono(cliente, promover_admin, db):
    """So o admin consegue registrar sessao em treino pessoal de jogador.
    O jogador sai mesmo assim: o treino fica sem dono, e a sessao do admin,
    intacta. Um treino pessoal SEM dependencia externa e apagado normalmente."""
    joao = token_joao(cliente)
    jid = eu(cliente, joao).json()["id"]
    usado = criar_treino(cliente, joao).json()
    # Editado: todas as versoes precisam ficar, nao so a usada.
    assert cliente.put(
        f"/v1/drills/{usado['id']}", json={**CORPO, "qtd_lances": 12}, headers=auth(joao)
    ).status_code == 200
    so_dele = criar_treino(cliente, joao).json()
    v_usada = usado["versao_atual"]["id"]
    enviar(cliente, joao, sessao(v_usada), sessao(so_dele["versao_atual"]["id"]))
    admin = token_admin(cliente, promover_admin)
    s_admin = sessao(v_usada, lances=[lance(1), lance(2)])
    assert enviar(cliente, admin, s_admin).json()["sessoes"][0]["situacao"] == "inserida"

    r = excluir(cliente, joao, {"senha": SENHA})

    assert r.status_code == 204
    db.expire_all()
    # O usado pelo admin fica sem dono, com as duas versoes.
    sobrevivente = db.get(Treino, usado["id"])
    assert sobrevivente is not None and sobrevivente.owner_id is None
    assert contar(db, TreinoVersao, TreinoVersao.treino_id == usado["id"]) == 2
    # O que so o Joao usava vai embora, com a versao.
    assert db.get(Treino, so_dele["id"]) is None
    assert contar(db, TreinoVersao, TreinoVersao.treino_id == so_dele["id"]) == 0
    # Nenhuma sessao do Joao sobra; a do admin fica, com os lances.
    assert contar(db, Sessao, Sessao.usuario_id == jid) == 0
    [do_admin] = db.query(Sessao).filter(Sessao.treino_versao_id == v_usada).all()
    assert str(do_admin.uuid_sessao) == s_admin["uuid_sessao"]
    assert contar(db, Lance, Lance.sessao_id == do_admin.id) == 2
    assert orfaos_na_auditoria(db) == [usado["id"]]


# --- Excluir conta: o que e apagado e o que fica -------------------------------


def test_exclusao_apaga_os_dados_e_mantem_a_auditoria_sem_vinculo(cliente, db):
    vitoria = token_vitoria(cliente)
    joao = token_joao(cliente)
    uid = eu(cliente, vitoria).json()["id"]
    jid = eu(cliente, joao).json()["id"]

    # Vitoria: um treino pessoal com duas versoes, uma copia de outro treino
    # dela (origem_id interno), duas sessoes com lances.
    treino = criar_treino(cliente, vitoria).json()
    editado = cliente.put(
        f"/v1/drills/{treino['id']}", json={**CORPO, "qtd_lances": 12}, headers=auth(vitoria)
    )
    assert editado.status_code == 200
    copia = cliente.post(f"/v1/drills/{treino['id']}/copy", headers=auth(vitoria)).json()
    v = treino["versao_atual"]["id"]
    enviar(cliente, vitoria, sessao(v), sessao(copia["versao_atual"]["id"]))
    # Joao: dados proprios, que nao podem ser tocados.
    treino_joao = criar_treino(cliente, joao).json()
    enviar(cliente, joao, sessao(treino_joao["versao_atual"]["id"]))

    sessoes_v = [s.id for s in db.query(Sessao).filter(Sessao.usuario_id == uid)]
    treinos_v = [t.id for t in db.query(Treino).filter(Treino.owner_id == uid)]
    assert len(sessoes_v) == 2 and len(treinos_v) == 2
    assert contar(db, Lance, Lance.sessao_id.in_(sessoes_v)) == 30
    auditoria_v = contar(db, LogAuditoria, LogAuditoria.usuario_id == uid)
    auditoria_total = contar(db, LogAuditoria)
    assert auditoria_v > 0
    antes_joao = (
        contar(db, Sessao, Sessao.usuario_id == jid),
        contar(db, Treino, Treino.owner_id == jid),
        contar(db, LogAuditoria, LogAuditoria.usuario_id == jid),
    )

    r = excluir(cliente, vitoria, {"senha": SENHA})
    assert r.status_code == 204
    assert r.content == b""

    # Apagado.
    assert contar(db, Usuario, Usuario.id == uid) == 0
    assert contar(db, Sessao, Sessao.usuario_id == uid) == 0
    assert contar(db, Lance, Lance.sessao_id.in_(sessoes_v)) == 0
    assert contar(db, Treino, Treino.id.in_(treinos_v)) == 0
    assert contar(db, TreinoVersao, TreinoVersao.treino_id.in_(treinos_v)) == 0
    # Auditoria: nenhuma linha some, nenhuma fica ligada a pessoa, e entra
    # o registro da exclusao (tambem sem vinculo).
    assert contar(db, LogAuditoria, LogAuditoria.usuario_id == uid) == 0
    assert contar(db, LogAuditoria) == auditoria_total + 1
    excluida = db.query(LogAuditoria).filter(LogAuditoria.acao == "conta_excluida").one()
    assert (excluida.usuario_id, excluida.entidade_id) == (None, None)
    # O Joao nao perdeu nada.
    assert (
        contar(db, Sessao, Sessao.usuario_id == jid),
        contar(db, Treino, Treino.owner_id == jid),
        contar(db, LogAuditoria, LogAuditoria.usuario_id == jid),
    ) == antes_joao


def test_copia_de_outra_pessoa_sobrevive_sem_o_vinculo_de_origem(cliente, promover_admin, db):
    joao = token_joao(cliente)
    do_joao = criar_treino(cliente, joao).json()
    admin = token_admin(cliente, promover_admin)
    copia = cliente.post(f"/v1/drills/{do_joao['id']}/copy", headers=auth(admin))
    assert copia.status_code == 201

    assert excluir(cliente, joao, {"senha": SENHA}).status_code == 204

    db.expire_all()
    sobrevivente = db.get(Treino, copia.json()["id"])
    assert sobrevivente is not None
    assert sobrevivente.origem_id is None


def test_depois_de_excluida_a_conta_some_sem_deixar_rastro(cliente):
    token = token_vitoria(cliente)
    assert excluir(cliente, token, {"senha": SENHA}).status_code == 204

    excluida = cliente.post("/v1/auth/login", json={"email": "vitoria@tobias.dev", "senha": SENHA})
    nunca_existiu = cliente.post("/v1/auth/login", json={"email": "ninguem@tobias.dev", "senha": SENHA})
    assert excluida.status_code == nunca_existiu.status_code == 401
    assert excluida.json() == nunca_existiu.json()

    # O token antigo, ainda dentro da validade, nao serve para mais nada.
    assert eu(cliente, token).status_code == 401
    assert excluir(cliente, token, {"senha": SENHA}).status_code == 401
    # E-mail e apelido ficam livres de novo.
    assert cadastrar(cliente, email="vitoria@tobias.dev", apelido="Vick").status_code == 201


# --- Ninguem mexe na conta de outro -------------------------------------------


def test_nao_exclui_a_conta_de_outro(cliente):
    vitoria = token_vitoria(cliente)
    joao = token_joao(cliente)

    # Token do Joao com a senha que tambem e a da Vitoria: exclui o JOAO.
    # A conta alvo vem sempre do token, nunca do corpo.
    r = excluir(cliente, joao, {"senha": SENHA, "id": 1, "email": "vitoria@tobias.dev"})
    assert r.status_code == 204
    assert eu(cliente, vitoria).status_code == 200
    assert eu(cliente, joao).status_code == 401


def test_nao_altera_a_conta_de_outro(cliente):
    vitoria = token_vitoria(cliente)
    joao = token_joao(cliente)
    id_vitoria = eu(cliente, vitoria).json()["id"]

    # Nao ha como apontar outra conta: o corpo so aceita o apelido.
    assert patch(cliente, joao, {"apelido": "Hacker", "id": id_vitoria}).status_code == 422
    r = patch(cliente, joao, {"apelido": "JoaoNovo"})
    assert r.json()["id"] != id_vitoria
    assert eu(cliente, vitoria).json()["apelido"] == "Vick"
    assert eu(cliente, joao).json()["apelido"] == "JoaoNovo"
