from tests.test_auth import cadastrar, logar


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def criar_jogador(cliente, email, apelido, cpf):
    cadastrar(cliente, email=email, apelido=apelido, cpf=cpf)
    return logar(cliente, email=email)


def token_vitoria(cliente):
    return criar_jogador(
        cliente, "vitoria@tobias.dev", "Vick", "11144477735"
    )


def token_joao(cliente):
    return criar_jogador(cliente, "joao@tobias.dev", "Joao", "52998224725")


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


def test_listagem_vazia_tem_envelope(cliente):
    token = token_vitoria(cliente)
    corpo = cliente.get("/v1/drills", headers=auth(token)).json()
    assert corpo == {"items": [], "total": 0, "limit": 20, "offset": 0}


def test_listagem_exige_token(cliente):
    assert cliente.get("/v1/drills").status_code in (401, 403)


def test_jogador_cria_treino_pessoal(cliente):
    token = token_vitoria(cliente)
    resposta = criar_treino(cliente, token)
    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["escopo"] == "pessoal"
    assert corpo["owner_id"] is not None
    assert corpo["versao_atual"]["numero"] == 1


def test_escopo_enviado_pelo_cliente_e_ignorado(cliente):
    token = token_vitoria(cliente)
    corpo = dict(CORPO, escopo="catalogo")
    resposta = criar_treino(cliente, token, corpo)
    assert resposta.status_code == 201
    assert resposta.json()["escopo"] == "pessoal"


def test_qtd_lances_fora_do_limite_e_recusada(cliente):
    token = token_vitoria(cliente)
    corpo = dict(CORPO, qtd_lances=500)
    assert criar_treino(cliente, token, corpo).status_code == 422


def test_limit_acima_do_maximo_e_recusado(cliente):
    token = token_vitoria(cliente)
    resposta = cliente.get("/v1/drills?limit=500", headers=auth(token))
    assert resposta.status_code == 422


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


def test_busca_filtra_por_titulo(cliente):
    token = token_vitoria(cliente)
    criar_treino(cliente, token)
    criar_treino(cliente, token, dict(CORPO, titulo="Resistencia"))

    corpo = cliente.get(
        "/v1/drills?busca=resist", headers=auth(token)
    ).json()
    assert corpo["total"] == 1
    assert corpo["items"][0]["titulo"] == "Resistencia"


def test_treino_inexistente_devolve_404(cliente):
    token = token_vitoria(cliente)
    resposta = cliente.get("/v1/drills/9999", headers=auth(token))
    assert resposta.status_code == 404