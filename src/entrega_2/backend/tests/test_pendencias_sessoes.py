"""Bola unica por sessao, calibracao com 1 casa, uuid_sessao no alerta e
ON DELETE CASCADE em lance.sessao_id."""

import logging
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import create_engine, delete, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from src.db.base import Base
from src.models.sessao import Lance, Sessao, TipoLance
from tests.test_sessoes import (
    alertas,
    contar,
    enviar,
    lance,
    lances_no_banco,
    sessao,
    sessao_no_banco,
    versao_de,
)
from tests.test_treinos import auth, token_vitoria
from tests import test_sessoes


@pytest.fixture(autouse=True)
def _banco_de_teste(abrir_db):
    """Os helpers de test_sessoes leem o banco por esta fabrica."""
    test_sessoes.SessionTeste = abrir_db


# --- Bola unica por sessao --------------------------------------------------


def test_bola_repetida_no_payload_da_422(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), lances=[lance(1), lance(2), lance(2)])

    r = enviar(cliente, token, s)

    assert r.status_code == 422
    assert "bola repetida" in r.text
    assert contar(Sessao) == 0


def test_mesmo_lance_repetido_continua_absorvido(cliente):
    """Reenvio do MESMO lance (mesmo uuid) nao e bola repetida."""
    token = token_vitoria(cliente)
    l = lance(1)
    s = sessao(versao_de(cliente, token), lances=[l, dict(l)])

    r = enviar(cliente, token, s)

    assert r.status_code == 200
    assert r.json()["sessoes"][0]["lances_duplicados"] == 1


def test_bola_ja_gravada_com_outro_lance_da_422_e_nao_500(cliente):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), lances=[lance(1), lance(2)])
    enviar(cliente, token, s)

    # Mesma sessao, mais tarde: um lance NOVO (outro uuid) com a bola 2.
    s2 = dict(s, lances=[lance(2), lance(3)])
    r = enviar(cliente, token, s2)

    assert r.status_code == 422
    assert "bola 2" in r.text
    # Nada do segundo envio foi gravado, nem o lance 3.
    assert [l.bola for l in lances_no_banco(s["uuid_sessao"])] == [1, 2]


def test_indice_unico_barra_bola_repetida_no_banco(cliente, abrir_db):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), lances=[lance(1)])
    enviar(cliente, token, s)
    [g] = sessao_no_banco(s["uuid_sessao"])

    db = abrir_db()
    try:
        db.add(
            Lance(
                sessao_id=g.id,
                uuid_lance=uuid.uuid4(),
                bola=1,
                resultado=TipoLance.acerto,
                ts_ms=5000,
            )
        )
        with pytest.raises(IntegrityError):
            db.commit()
    finally:
        db.rollback()
        db.close()


# --- Calibracao com 1 casa -------------------------------------------------


def calibrar(cliente, token, valor):
    return cliente.put(
        "/v1/auth/calibracao", json={"calibracao": valor}, headers=auth(token)
    )


@pytest.mark.parametrize("valor", [2.25, 0.05, 10.123])
def test_calibracao_com_mais_de_uma_casa_da_422(cliente, valor):
    token = token_vitoria(cliente)
    assert calibrar(cliente, token, valor).status_code == 422


@pytest.mark.parametrize("valor", [0, 2.5, 45, 12.0])
def test_calibracao_com_uma_casa_e_aceita(cliente, valor):
    token = token_vitoria(cliente)
    r = calibrar(cliente, token, valor)
    assert r.status_code == 200
    assert r.json()["calibracao"] == pytest.approx(valor)


@pytest.mark.parametrize("valor", [-0.1, 45.1])
def test_calibracao_fora_da_faixa_da_422(cliente, valor):
    token = token_vitoria(cliente)
    assert calibrar(cliente, token, valor).status_code == 422


def test_calibracao_aceita_e_a_mesma_regra_da_dificuldade(cliente):
    """O valor que o servidor guarda volta, intacto, como dificuldade."""
    token = token_vitoria(cliente)
    guardada = calibrar(cliente, token, 7.5).json()["calibracao"]
    s = sessao(versao_de(cliente, token), dificuldade=guardada)
    assert enviar(cliente, token, s).status_code == 200


# --- uuid_sessao no alerta de divergencia ----------------------------------


def test_alerta_de_divergencia_traz_o_uuid_sessao(cliente, caplog):
    token = token_vitoria(cliente)
    s = sessao(versao_de(cliente, token), pontuacao_cliente=3000)

    with caplog.at_level(logging.WARNING, logger="tobias.pontuacao"):
        enviar(cliente, token, s)

    [alerta] = alertas(caplog)
    assert alerta.uuid_sessao == s["uuid_sessao"]
    assert f"uuid_sessao={s['uuid_sessao']}" in alerta.getMessage()


# --- ON DELETE CASCADE -----------------------------------------------------


def test_apagar_sessao_por_sql_leva_os_lances():
    """Com chaves estrangeiras LIGADAS (o SQLite as desliga por padrao)."""
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    try:
        # Sem usuario/treino de verdade: insere com FK desligada, liga depois.
        db.execute(text("PRAGMA foreign_keys=OFF"))
        s = Sessao(
            uuid_sessao=uuid.uuid4(),
            usuario_id=1,
            treino_versao_id=1,
            iniciada_em=datetime(2026, 11, 5, tzinfo=timezone.utc),
        )
        db.add(s)
        db.flush()
        db.add_all(
            Lance(
                sessao_id=s.id,
                uuid_lance=uuid.uuid4(),
                bola=b,
                resultado=TipoLance.acerto,
                ts_ms=b * 1000,
            )
            for b in (1, 2, 3)
        )
        db.commit()
        db.execute(text("PRAGMA foreign_keys=ON"))

        # SQL puro, sem passar pelo painel nem pelo ORM.
        db.execute(delete(Sessao).where(Sessao.id == s.id))
        db.commit()

        assert db.query(Sessao).count() == 0
        assert db.query(Lance).count() == 0
    finally:
        db.close()
        engine.dispose()
