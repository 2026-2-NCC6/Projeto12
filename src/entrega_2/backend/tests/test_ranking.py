"""GET /v1/ranking: ordem das tres metricas, posicao de quem chama e privacidade."""

import uuid
from datetime import date, datetime, timedelta, timezone

import pytest
from sqlalchemy.exc import IntegrityError

from src.main import app
from src.models.sessao import Sessao
from src.models.usuario import Usuario
from src.routers.ranking import agora
from tests.test_auth import logar
from tests.test_treinos import auth, criar_treino

# Sexta, 06/11/2026, 12:00 em Sao Paulo.
AGORA = datetime(2026, 11, 6, 15, 0, tzinfo=timezone.utc)
SP = timezone(timedelta(hours=-3))  # so para escrever horarios locais nos testes
ADULTO = date(1990, 1, 1)
MENOR = date(2012, 3, 15)


@pytest.fixture
def mundo(cliente, abrir_db):
    """Relogio fixo, um treino para pendurar sessoes e fabricas de dados."""
    app.dependency_overrides[agora] = lambda: AGORA

    criados = []  # (email, nome) de todo mundo, para a varredura de privacidade

    def jogador(apelido, nascimento=ADULTO, com_login=False):
        email = f"{apelido.lower()}@tobias.dev"
        nome = f"Nome Completo de {apelido}"
        criados.append((email, nome))
        if com_login:
            r = cliente.post(
                "/v1/auth/cadastro",
                json={
                    "email": email,
                    "senha": "senha12345",
                    "nome": nome,
                    "apelido": apelido,
                    "data_nascimento": nascimento.isoformat(),
                    "perfil": "casual",
                },
            )
            assert r.status_code == 201, r.text
            return logar(cliente, email=email)
        db = abrir_db()
        db.add(
            Usuario(
                email=email,
                senha_hash="x",
                nome=nome,
                apelido=apelido,
                data_nascimento=nascimento,
            )
        )
        db.commit()
        db.close()
        return None

    # Treino criado por um usuario a parte, so para ter uma versao valida.
    dono = jogador("DonoDoTreino", com_login=True)
    versao_id = criar_treino(cliente, dono).json()["versao_atual"]["id"]

    def sessoes(apelido, *itens):
        """itens: (instante, pontuacao). Gravadas direto, em UTC, como a ingestao."""
        db = abrir_db()
        usuario_id = db.query(Usuario.id).filter(Usuario.apelido == apelido).scalar()
        for instante, pontos in itens:
            db.add(
                Sessao(
                    uuid_sessao=uuid.uuid4(),
                    usuario_id=usuario_id,
                    treino_versao_id=versao_id,
                    iniciada_em=instante.astimezone(timezone.utc),
                    pontuacao_total=pontos,
                )
            )
        db.commit()
        db.close()

    def ranking(token, metrica):
        r = cliente.get("/v1/ranking", params={"metrica": metrica}, headers=auth(token))
        assert r.status_code == 200, r.text
        return r.json()

    class Mundo:
        pass

    m = Mundo()
    m.jogador, m.sessoes, m.ranking, m.criados = jogador, sessoes, ranking, criados
    return m


def dias_atras(n, hora_utc=12):
    return (AGORA - timedelta(days=n)).replace(hour=hora_utc)


def lista(corpo):
    return [(i["posicao"], i["apelido"], i["valor"]) for i in corpo["itens"]]


# --- Acesso -----------------------------------------------------------------


def test_exige_token(cliente):
    assert cliente.get("/v1/ranking", params={"metrica": "pontos"}).status_code == 401


@pytest.mark.parametrize("params", [{}, {"metrica": "vitorias"}])
def test_metrica_ausente_ou_invalida_422(mundo, cliente, params):
    token = mundo.jogador("Eu", com_login=True)
    assert cliente.get("/v1/ranking", params=params, headers=auth(token)).status_code == 422


# --- Pontos -----------------------------------------------------------------


def test_pontos_soma_30_dias_e_desempata_pelo_apelido(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    for a in ("Gama", "Alfa", "Beta"):
        mundo.jogador(a)
    mundo.sessoes("Beta", (dias_atras(1), 100), (dias_atras(29), 200))
    mundo.sessoes("Gama", (dias_atras(2), 100))
    mundo.sessoes(
        "Alfa",
        (dias_atras(3), 100),
        (dias_atras(31), 5000),  # fora dos 30 dias
        (dias_atras(4), None),  # ainda nao pontuada: nao conta
    )

    corpo = mundo.ranking(eu, "pontos")

    assert lista(corpo) == [(1, "Beta", 300), (2, "Alfa", 100), (3, "Gama", 100)]
    assert [i["sessoes"] for i in corpo["itens"]] == [2, 1, 1]
    assert corpo["periodo"] == {
        "de": "2026-10-07T15:00:00Z",
        "ate": "2026-11-06T15:00:00Z",
    }
    # Sem sessao no periodo: voce nulo.
    assert corpo["voce"] is None
    # Estavel: a mesma chamada da a mesma ordem.
    assert mundo.ranking(eu, "pontos")["itens"] == corpo["itens"]


def test_voce_traz_a_posicao_real_fora_dos_20(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    for n in range(25):
        mundo.jogador(f"J{n:02d}")
        mundo.sessoes(f"J{n:02d}", (dias_atras(1), 1000 - n))
    mundo.sessoes("Eu", (dias_atras(1), 10))  # o ultimo de 26

    corpo = mundo.ranking(eu, "pontos")

    assert len(corpo["itens"]) == 20
    assert corpo["itens"][0]["apelido"] == "J00"
    assert corpo["itens"][-1] == {"posicao": 20, "apelido": "J19", "valor": 981, "sessoes": 1}
    assert "Eu" not in [i["apelido"] for i in corpo["itens"]]
    assert corpo["voce"] == {
        "posicao": 26,
        "apelido": "Eu",
        "valor": 10,
        "sessoes": 1,
        "oculto": False,
    }


def test_voce_dentro_dos_20_bate_com_a_lista(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    mundo.jogador("Ana")
    mundo.jogador("Zeca")
    mundo.sessoes("Ana", (dias_atras(1), 500))
    mundo.sessoes("Eu", (dias_atras(1), 300))
    mundo.sessoes("Zeca", (dias_atras(1), 300))  # empata comigo; "Eu" < "Zeca"

    corpo = mundo.ranking(eu, "pontos")

    assert lista(corpo) == [(1, "Ana", 500), (2, "Eu", 300), (3, "Zeca", 300)]
    assert corpo["voce"] == {**corpo["itens"][1], "oculto": False}


# --- Privacidade: menores e quem nao tem data -------------------------------


def test_menor_nao_aparece_mas_ve_a_propria_posicao(mundo):
    menor = mundo.jogador("Juninho", nascimento=MENOR, com_login=True)
    adulto = mundo.jogador("Adulta", com_login=True)
    mundo.jogador("Outro")
    mundo.sessoes("Juninho", (dias_atras(1), 900))
    mundo.sessoes("Adulta", (dias_atras(1), 500))
    mundo.sessoes("Outro", (dias_atras(1), 100))

    visto_pelo_adulto = mundo.ranking(adulto, "pontos")
    visto_pelo_menor = mundo.ranking(menor, "pontos")

    # A lista e a mesma para todos, sem o menor, e as posicoes nao pulam.
    assert lista(visto_pelo_adulto) == [(1, "Adulta", 500), (2, "Outro", 100)]
    assert visto_pelo_menor["itens"] == visto_pelo_adulto["itens"]
    # O menor ve onde estaria: ninguem publico esta a frente dele.
    assert visto_pelo_menor["voce"] == {
        "posicao": 1,
        "apelido": "Juninho",
        "valor": 900,
        "sessoes": 1,
        "oculto": True,
    }
    assert visto_pelo_adulto["voce"]["posicao"] == 1
    assert visto_pelo_adulto["voce"]["oculto"] is False


def test_maioridade_conta_do_dia_do_aniversario(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    # Hoje e 06/11/2026 em Sao Paulo.
    mundo.jogador("FezHoje", nascimento=date(2008, 11, 6))
    mundo.jogador("FazAmanha", nascimento=date(2008, 11, 7))
    mundo.sessoes("FezHoje", (dias_atras(1), 100))
    mundo.sessoes("FazAmanha", (dias_atras(1), 200))

    assert [a for _, a, _ in lista(mundo.ranking(eu, "pontos"))] == ["FezHoje"]


def test_sem_data_de_nascimento_fica_fora(mundo, abrir_db):
    eu = mundo.jogador("Eu", com_login=True)
    db = abrir_db()
    db.add(Usuario(email="sem@tobias.dev", senha_hash="x", nome="Sem Data", apelido="SemData"))
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        # Hoje a coluna e NOT NULL e o caso nao existe. A regra continua no
        # codigo; este teste passa a valer sozinho se a coluna ficar opcional.
        pytest.skip("usuario.data_nascimento e NOT NULL: caso impossivel no schema atual")
    finally:
        db.close()
    mundo.sessoes("SemData", (dias_atras(1), 999))

    assert lista(mundo.ranking(eu, "pontos")) == []


# --- Frequencia -------------------------------------------------------------


def test_frequencia_conta_dias_distintos_dos_ultimos_7(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    mundo.jogador("Assidua")
    mundo.jogador("Rara")
    mundo.sessoes(
        "Assidua",
        *[(dias_atras(d), 10) for d in range(6)],  # 6 dias
        (dias_atras(2, hora_utc=18), 10),  # segunda sessao num dia ja contado
    )
    mundo.sessoes("Rara", (dias_atras(1), 10), (dias_atras(8), 10))  # 8 dias: fora
    mundo.sessoes("Eu", (dias_atras(0), 10), (dias_atras(3), 10))

    corpo = mundo.ranking(eu, "frequencia")

    assert lista(corpo) == [(1, "Assidua", 6), (2, "Eu", 2), (3, "Rara", 1)]
    assert corpo["itens"][0]["sessoes"] == 7
    # 7 dias de calendario em Sao Paulo: de 31/10 00:00 local ate agora.
    assert corpo["periodo"]["de"] == "2026-10-31T03:00:00Z"
    assert corpo["voce"]["posicao"] == 2


def test_frequencia_22h_e_23h_do_mesmo_dia_local_sao_um_dia(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    mundo.sessoes(
        "Eu",
        (datetime(2026, 11, 4, 22, 0, tzinfo=SP), 10),  # 05/11 01:00Z
        (datetime(2026, 11, 4, 23, 0, tzinfo=SP), 10),  # 05/11 02:00Z
    )
    assert mundo.ranking(eu, "frequencia")["voce"]["valor"] == 1


def test_frequencia_usa_o_dia_de_sao_paulo_e_nao_o_de_utc(mundo):
    # O teste acima nao separa os dois fusos (22h e 23h caem no mesmo dia em
    # UTC tambem). Estes dois casos separam, um em cada direcao.
    eu = mundo.jogador("Eu", com_login=True)
    mundo.jogador("Noturna")
    # Mesmo dia em SP (04/11), dias diferentes em UTC (04 e 05/11): 1 dia.
    mundo.sessoes(
        "Eu",
        (datetime(2026, 11, 4, 20, 0, tzinfo=SP), 10),  # 04/11 23:00Z
        (datetime(2026, 11, 4, 22, 0, tzinfo=SP), 10),  # 05/11 01:00Z
    )
    # Dias diferentes em SP (03 e 04/11), mesmo dia em UTC (04/11): 2 dias.
    mundo.sessoes(
        "Noturna",
        (datetime(2026, 11, 3, 22, 0, tzinfo=SP), 10),  # 04/11 01:00Z
        (datetime(2026, 11, 4, 10, 0, tzinfo=SP), 10),  # 04/11 13:00Z
    )

    corpo = mundo.ranking(eu, "frequencia")
    assert lista(corpo) == [(1, "Noturna", 2), (2, "Eu", 1)]


def test_frequencia_comeca_na_meia_noite_local(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    mundo.jogador("NaBorda")
    mundo.sessoes(
        "Eu",
        (datetime(2026, 10, 30, 23, 59, tzinfo=SP), 10),  # 8o dia: fora
    )
    mundo.sessoes("NaBorda", (datetime(2026, 10, 31, 0, 0, tzinfo=SP), 10))  # 1o dia

    corpo = mundo.ranking(eu, "frequencia")
    assert lista(corpo) == [(1, "NaBorda", 1)]
    assert corpo["voce"] is None


# --- Evolucao ---------------------------------------------------------------


def atual(*pontos):
    return [(dias_atras(1 + i), p) for i, p in enumerate(pontos)]


def anterior(*pontos):
    return [(dias_atras(31 + i), p) for i, p in enumerate(pontos)]


def test_evolucao_ordena_pela_variacao_percentual(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    for a in ("Dobrou", "Estavel", "Caiu"):
        mundo.jogador(a)
    mundo.sessoes("Dobrou", *anterior(100, 100, 100), *atual(200, 200, 200))  # +100%
    mundo.sessoes("Estavel", *anterior(100, 100, 100), *atual(100, 100, 100))  # 0%
    mundo.sessoes("Caiu", *anterior(300, 300, 300), *atual(100, 100, 100))  # -66,7%
    mundo.sessoes("Eu", *anterior(100, 100, 100), *atual(110, 110, 110, 110))  # +46,7%

    corpo = mundo.ranking(eu, "evolucao")

    assert lista(corpo) == [
        (1, "Dobrou", 100.0),
        (2, "Eu", 46.7),
        (3, "Estavel", 0.0),
        (4, "Caiu", -66.7),
    ]
    # `sessoes` conta as do periodo atual.
    assert corpo["voce"] == {
        "posicao": 2,
        "apelido": "Eu",
        "valor": 46.7,
        "sessoes": 4,
        "oculto": False,
    }
    assert corpo["periodo"] == {
        "de": "2026-10-07T15:00:00Z",
        "ate": "2026-11-06T15:00:00Z",
    }


def test_evolucao_exige_3_sessoes_em_cada_periodo(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    for a in ("Sortudo", "Novato", "Constante"):
        mundo.jogador(a)
    # 1 sessao no mes passado e 2 neste: seria +100% e lideraria.
    mundo.sessoes("Sortudo", *anterior(100), *atual(100, 100))
    # So treinou neste periodo.
    mundo.sessoes("Novato", *atual(500, 500, 500))
    mundo.sessoes("Constante", *anterior(100, 100, 100), *atual(105, 105, 105))
    # Eu: 3 neste, so 2 no anterior. Fora da metrica, e nao com zero.
    mundo.sessoes("Eu", *anterior(10, 10), *atual(900, 900, 900))

    corpo = mundo.ranking(eu, "evolucao")

    assert lista(corpo) == [(1, "Constante", 5.0)]
    assert corpo["voce"] is None


def test_evolucao_ignora_sessoes_alem_de_60_dias(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    mundo.sessoes(
        "Eu",
        *anterior(100, 100),
        (dias_atras(61), 100),  # completaria 3 no anterior, mas esta fora
        *atual(100, 100, 100),
    )
    assert mundo.ranking(eu, "evolucao")["voce"] is None


# --- oculto: fora por regra x abaixo do corte -------------------------------


def test_oculto_distingue_regra_de_privacidade_de_corte_dos_20(mundo):
    """Adulto em 25o ESTA no ranking publico, so nao cabe nos 20: dizer que
    ele "nao aparece" seria falso. Menor esta fora por regra."""
    adulto = mundo.jogador("Adulto25", com_login=True)
    menor = mundo.jogador("Juninho", nascimento=MENOR, com_login=True)
    # Faz 18 amanha (hoje e 06/11/2026 em SP): ainda menor hoje.
    quase = mundo.jogador("Quase18", nascimento=date(2008, 11, 7), com_login=True)
    for n in range(24):
        mundo.jogador(f"J{n:02d}")
        mundo.sessoes(f"J{n:02d}", (dias_atras(1), 1000 - n))
    mundo.sessoes("Adulto25", (dias_atras(1), 500))
    mundo.sessoes("Juninho", (dias_atras(1), 2000))  # estaria em 1o
    mundo.sessoes("Quase18", (dias_atras(1), 600))

    do_adulto = mundo.ranking(adulto, "pontos")["voce"]
    do_menor = mundo.ranking(menor, "pontos")["voce"]
    do_quase = mundo.ranking(quase, "pontos")["voce"]

    assert (do_adulto["posicao"], do_adulto["oculto"]) == (25, False)
    assert (do_menor["posicao"], do_menor["oculto"]) == (1, True)
    assert (do_quase["posicao"], do_quase["oculto"]) == (25, True)


def test_oculto_so_existe_no_voce_e_nunca_nas_linhas_dos_outros(mundo):
    eu = mundo.jogador("Eu", com_login=True)
    mundo.jogador("Ana")
    mundo.sessoes("Ana", (dias_atras(1), 500))
    mundo.sessoes("Eu", (dias_atras(1), 300))

    for metrica in ("pontos", "frequencia"):
        corpo = mundo.ranking(eu, metrica)
        assert corpo["itens"]
        assert all("oculto" not in i for i in corpo["itens"]), metrica
        assert corpo["voce"]["oculto"] is False


# --- Privacidade: o que sai na resposta --------------------------------------

CHAVES_PERMITIDAS = {
    "metrica",
    "periodo",
    "de",
    "ate",
    "itens",
    "voce",
    "posicao",
    "apelido",
    "valor",
    "sessoes",
}


def varrer(no, caminho="$"):
    """Todas as (caminho, chave) e (caminho, valor-texto) do JSON."""
    if isinstance(no, dict):
        for k, v in no.items():
            yield ("chave", f"{caminho}.{k}", k)
            yield from varrer(v, f"{caminho}.{k}")
    elif isinstance(no, list):
        for i, v in enumerate(no):
            yield from varrer(v, f"{caminho}[{i}]")
    elif isinstance(no, str):
        yield ("texto", caminho, no)


def test_nada_alem_do_apelido(mundo, abrir_db):
    """A rota mais sensivel da API: um usuario vendo dados de outro.

    Varre o JSON inteiro, de todas as metricas, vistas por um adulto e por
    um menor: so chaves conhecidas, e nenhum e-mail, nome ou id de usuario
    em lugar nenhum, nem dentro de outro texto.
    """
    tokens = {
        "adulto": mundo.jogador("Adulta", com_login=True),
        "menor": mundo.jogador("Juninho", nascimento=MENOR, com_login=True),
    }
    for a in ("Bruno", "Carla"):
        mundo.jogador(a)
    for a in ("Adulta", "Juninho", "Bruno", "Carla"):
        mundo.sessoes(a, *anterior(100, 100, 100), *atual(150, 120, 130))

    db = abrir_db()
    ids = {str(i) for (i,) in db.query(Usuario.id).all()}
    db.close()
    proibidos = {t for par in mundo.criados for t in par}  # e-mails e nomes

    respostas = 0
    for token in tokens.values():
        for metrica in ("pontos", "frequencia", "evolucao"):
            corpo = mundo.ranking(token, metrica)
            assert corpo["itens"], metrica  # varrer lista vazia nao provaria nada
            assert corpo["voce"] is not None, metrica
            respostas += 1
            for tipo, caminho, valor in varrer(corpo):
                if tipo == "chave":
                    # `oculto` e da propria pessoa: so vale dentro de `voce`.
                    if caminho == "$.voce.oculto":
                        continue
                    assert valor in CHAVES_PERMITIDAS, f"campo inesperado {caminho}"
                else:
                    for p in proibidos:
                        assert p.lower() not in valor.lower(), f"{caminho} vaza {p!r}"
                    assert "@" not in valor, f"{caminho} parece e-mail: {valor!r}"
                    if caminho.endswith(".apelido"):
                        assert valor not in ids, f"{caminho} parece id"
    assert respostas == 6
