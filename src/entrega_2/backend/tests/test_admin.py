from tests.test_treinos import auth, token_admin, token_vitoria


def test_rota_admin_nega_jogador(cliente):
    token = token_vitoria(cliente)
    resposta = cliente.get("/v1/admin/usuarios", headers=auth(token))
    assert resposta.status_code == 403


def test_rota_admin_exige_token(cliente):
    assert cliente.get("/v1/admin/usuarios").status_code in (401, 403)


def test_admin_lista_usuarios(cliente, promover_admin):
    token = token_admin(cliente, promover_admin)
    resposta = cliente.get("/v1/admin/usuarios", headers=auth(token))

    assert resposta.status_code == 200
    corpo = resposta.json()
    assert corpo["total"] == 1
    assert corpo["items"][0]["email"] == "vitoria@tobias.dev"


def test_listagem_de_usuarios_nao_vaza_dados_pessoais(cliente, promover_admin):
    token = token_admin(cliente, promover_admin)
    corpo = cliente.get("/v1/admin/usuarios", headers=auth(token)).json()

    usuario = corpo["items"][0]
    assert "cpf" not in usuario
    assert "data_nascimento" not in usuario
    assert "senha_hash" not in usuario