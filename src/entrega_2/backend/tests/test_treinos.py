from tests.test_auth import cadastrar, logar


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def criar_jogador(cliente, email, apelido):
    cadastrar(cliente, email=email, apelido=apelido)
    return logar(cliente, email=email)


def token_vitoria(cliente):
    return criar_jogador(
        cliente, "vitoria@tobias.dev", "Vick"
    )


def token_joao(cliente):
    return criar_jogador(cliente, "joao@tobias.dev", "Joao")


def token_admin(cliente, promover):
    """Cria a Vitoria, promove a admin e devolve um token novo.

    O papel vai dentro do token, entao e preciso logar de novo
    depois de promover.
    """
    token_vitoria(cliente)
    promover()
    return logar(cliente, email="vitoria@tobias.dev")


CORPO = {
    "titulo": "Reacao turbo",
    "descricao": "Sequencia rapida para aquecer",
    "nivel": "medio",
    "qtd_lances": 20,
    "intervalo_ms": 3000,
    "falas_tobias": True,
}


def criar_treino(cliente, token, corpo=None):
    return cliente.post("/v1/drills", json=corpo or CORPO, headers=auth(token))


# --- Listagem -------------------------------------------------------------


def test_listagem_vazia_tem_envelope(cliente):
    token = token_vitoria(cliente)
    corpo = cliente.get("/v1/drills", headers=auth(token)).json()
    assert corpo == {"items": [], "total": 0, "limit": 20, "offset": 0}


def test_listagem_exige_token(cliente):
    assert cliente.get("/v1/drills").status_code in (401, 403)


def test_busca_filtra_por_titulo(cliente):
    token = token_vitoria(cliente)
    criar_treino(cliente, token)
    criar_treino(cliente, token, dict(CORPO, titulo="Resistencia"))

    corpo = cliente.get(
        "/v1/drills?busca=resist", headers=auth(token)
    ).json()
    assert corpo["total"] == 1
    assert corpo["items"][0]["titulo"] == "Resistencia"


def test_limit_acima_do_maximo_e_recusado(cliente):
    token = token_vitoria(cliente)
    resposta = cliente.get("/v1/drills?limit=500", headers=auth(token))
    assert resposta.status_code == 422


def test_treino_inexistente_devolve_404(cliente):
    token = token_vitoria(cliente)
    resposta = cliente.get("/v1/drills/9999", headers=auth(token))
    assert resposta.status_code == 404


# --- Criacao e escopo -----------------------------------------------------


def test_jogador_cria_treino_pessoal(cliente):
    token = token_vitoria(cliente)
    resposta = criar_treino(cliente, token)
    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["escopo"] == "pessoal"
    assert corpo["owner_id"] is not None
    assert corpo["versao_atual"]["numero"] == 1


def test_admin_cria_treino_de_catalogo(cliente, promover_admin):
    token = token_admin(cliente, promover_admin)
    resposta = criar_treino(cliente, token)
    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["escopo"] == "catalogo"
    assert corpo["owner_id"] is None


def test_escopo_enviado_pelo_cliente_e_ignorado(cliente):
    token = token_vitoria(cliente)
    corpo = dict(CORPO, escopo="catalogo")
    resposta = criar_treino(cliente, token, corpo)
    assert resposta.status_code == 201
    assert resposta.json()["escopo"] == "pessoal"
    assert resposta.json()["owner_id"] is not None


def test_qtd_lances_fora_do_limite_e_recusada(cliente):
    token = token_vitoria(cliente)
    corpo = dict(CORPO, qtd_lances=500)
    assert criar_treino(cliente, token, corpo).status_code == 422


# --- Controle de acesso entre jogadores (US-802) --------------------------


def test_jogador_nao_ve_treino_pessoal_de_outro(cliente):
    token_a = token_vitoria(cliente)
    treino_id = criar_treino(cliente, token_a).json()["id"]

    token_b = token_joao(cliente)
    resposta = cliente.get(f"/v1/drills/{treino_id}", headers=auth(token_b))
    assert resposta.status_code == 404


def test_jogador_nao_lista_treino_pessoal_de_outro(cliente):
    token_a = token_vitoria(cliente)
    criar_treino(cliente, token_a)

    token_b = token_joao(cliente)
    corpo = cliente.get("/v1/drills", headers=auth(token_b)).json()
    assert corpo["total"] == 0


def test_jogador_nao_edita_treino_de_outro(cliente):
    token_a = token_vitoria(cliente)
    treino_id = criar_treino(cliente, token_a).json()["id"]

    token_b = token_joao(cliente)
    resposta = cliente.put(
        f"/v1/drills/{treino_id}", json=CORPO, headers=auth(token_b)
    )
    assert resposta.status_code == 404


def test_jogador_nao_copia_treino_de_outro(cliente):
    token_a = token_vitoria(cliente)
    treino_id = criar_treino(cliente, token_a).json()["id"]

    token_b = token_joao(cliente)
    resposta = cliente.post(
        f"/v1/drills/{treino_id}/copy", headers=auth(token_b)
    )
    assert resposta.status_code == 404


# --- Protecao do catalogo (US-802) ----------------------------------------


def test_jogador_nao_edita_treino_de_catalogo(cliente, promover_admin):
    admin = token_admin(cliente, promover_admin)
    treino_id = criar_treino(cliente, admin).json()["id"]

    jogador = token_joao(cliente)
    resposta = cliente.put(
        f"/v1/drills/{treino_id}", json=CORPO, headers=auth(jogador)
    )
    assert resposta.status_code == 404


def test_jogador_nao_exclui_treino_de_catalogo(cliente, promover_admin):
    admin = token_admin(cliente, promover_admin)
    treino_id = criar_treino(cliente, admin).json()["id"]

    jogador = token_joao(cliente)
    resposta = cliente.delete(
        f"/v1/drills/{treino_id}", headers=auth(jogador)
    )
    assert resposta.status_code == 403


def test_jogador_ve_o_catalogo(cliente, promover_admin):
    admin = token_admin(cliente, promover_admin)
    criar_treino(cliente, admin)

    jogador = token_joao(cliente)
    corpo = cliente.get("/v1/drills", headers=auth(jogador)).json()
    assert corpo["total"] == 1
    assert corpo["items"][0]["escopo"] == "catalogo"


# --- Copia (copy-on-write) ------------------------------------------------


def test_copia_guarda_a_origem(cliente):
    token = token_vitoria(cliente)
    original_id = criar_treino(cliente, token).json()["id"]

    resposta = cliente.post(
        f"/v1/drills/{original_id}/copy", headers=auth(token)
    )
    assert resposta.status_code == 201
    copia = resposta.json()
    assert copia["origem_id"] == original_id
    assert copia["escopo"] == "pessoal"
    assert copia["id"] != original_id


def test_copia_nao_altera_o_original(cliente):
    token = token_vitoria(cliente)
    original_id = criar_treino(cliente, token).json()["id"]
    cliente.post(f"/v1/drills/{original_id}/copy", headers=auth(token))

    original = cliente.get(
        f"/v1/drills/{original_id}", headers=auth(token)
    ).json()
    assert original["origem_id"] is None
    assert original["versao_atual"]["qtd_lances"] == 20


# --- Versionamento --------------------------------------------------------


def test_edicao_cria_versao_nova_sem_apagar_a_anterior(cliente):
    token = token_vitoria(cliente)
    treino_id = criar_treino(cliente, token).json()["id"]

    corpo = dict(CORPO, qtd_lances=15)
    resposta = cliente.put(
        f"/v1/drills/{treino_id}", json=corpo, headers=auth(token)
    )
    assert resposta.status_code == 200
    assert resposta.json()["versao_atual"]["numero"] == 2

    versoes = cliente.get(
        f"/v1/drills/{treino_id}/versions", headers=auth(token)
    ).json()
    assert len(versoes) == 2
    assert versoes[0]["qtd_lances"] == 15
    assert versoes[1]["qtd_lances"] == 20


# --- Exclusao logica ------------------------------------------------------


def test_jogador_exclui_o_proprio_treino(cliente):
    token = token_vitoria(cliente)
    treino_id = criar_treino(cliente, token).json()["id"]

    resposta = cliente.delete(
        f"/v1/drills/{treino_id}", headers=auth(token)
    )
    assert resposta.status_code == 204

    assert cliente.get(
        f"/v1/drills/{treino_id}", headers=auth(token)
    ).status_code == 404


def test_treino_excluido_some_da_listagem(cliente):
    token = token_vitoria(cliente)
    treino_id = criar_treino(cliente, token).json()["id"]
    cliente.delete(f"/v1/drills/{treino_id}", headers=auth(token))

    corpo = cliente.get("/v1/drills", headers=auth(token)).json()
    assert corpo["total"] == 0


def test_excluir_duas_vezes_devolve_404(cliente):
    token = token_vitoria(cliente)
    treino_id = criar_treino(cliente, token).json()["id"]
    cliente.delete(f"/v1/drills/{treino_id}", headers=auth(token))

    resposta = cliente.delete(
        f"/v1/drills/{treino_id}", headers=auth(token)
    )
    assert resposta.status_code == 404


def test_admin_exclui_treino_de_catalogo(cliente, promover_admin):
    token = token_admin(cliente, promover_admin)
    treino_id = criar_treino(cliente, token).json()["id"]

    resposta = cliente.delete(
        f"/v1/drills/{treino_id}", headers=auth(token)
    )
    assert resposta.status_code == 204