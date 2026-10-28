def cadastrar(cliente, email="jogador@tobias.dev", senha="senha12345"):
    return cliente.post(
        "/v1/auth/cadastro", json={"email": email, "senha": senha}
    )


def logar(cliente, email="jogador@tobias.dev", senha="senha12345"):
    resposta = cliente.post(
        "/v1/auth/login", json={"email": email, "senha": senha}
    )
    return resposta.json()["access_token"]


def test_cadastro_cria_jogador(cliente):
    resposta = cadastrar(cliente)
    assert resposta.status_code == 201
    corpo = resposta.json()
    assert corpo["email"] == "jogador@tobias.dev"
    assert corpo["papel"] == "jogador"


def test_cadastro_nao_vaza_senha(cliente):
    corpo = cadastrar(cliente).json()
    assert "senha" not in corpo
    assert "senha_hash" not in corpo


def test_email_duplicado_e_recusado(cliente):
    cadastrar(cliente)
    assert cadastrar(cliente).status_code == 409


def test_senha_curta_e_recusada(cliente):
    assert cadastrar(cliente, senha="123").status_code == 422


def test_login_devolve_token(cliente):
    cadastrar(cliente)
    resposta = cliente.post(
        "/v1/auth/login",
        json={"email": "jogador@tobias.dev", "senha": "senha12345"},
    )
    assert resposta.status_code == 200
    assert resposta.json()["token_type"] == "bearer"


def test_senha_errada_e_recusada(cliente):
    cadastrar(cliente)
    resposta = cliente.post(
        "/v1/auth/login",
        json={"email": "jogador@tobias.dev", "senha": "errada12345"},
    )
    assert resposta.status_code == 401


def test_email_inexistente_responde_igual_a_senha_errada(cliente):
    resposta = cliente.post(
        "/v1/auth/login",
        json={"email": "ninguem@tobias.dev", "senha": "senha12345"},
    )
    assert resposta.status_code == 401
    assert resposta.json()["detail"] == "Credenciais invalidas"


def test_rota_protegida_sem_token(cliente):
    assert cliente.get("/v1/auth/eu").status_code in (401, 403)


def test_rota_protegida_com_token(cliente):
    cadastrar(cliente)
    token = logar(cliente)
    resposta = cliente.get(
        "/v1/auth/eu", headers={"Authorization": f"Bearer {token}"}
    )
    assert resposta.status_code == 200
    assert resposta.json()["email"] == "jogador@tobias.dev"


def test_token_falsificado_e_recusado(cliente):
    cadastrar(cliente)
    token = logar(cliente)
    adulterado = token[:-3] + "xyz"
    resposta = cliente.get(
        "/v1/auth/eu", headers={"Authorization": f"Bearer {adulterado}"}
    )
    assert resposta.status_code == 401