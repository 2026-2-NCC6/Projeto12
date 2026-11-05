import asyncio
import uuid
from datetime import datetime, timezone

import pytest
from fastapi import FastAPI
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from src.admin.painel import LanceView, SessaoView, montar_painel
from src.db.base import Base
from src.models.sessao import Lance, Sessao, TipoLance


def test_sessao_e_lance_registradas_no_painel():
    painel = montar_painel(FastAPI(), "segredo-de-teste")
    assert {v.identity for v in painel.views} >= {"sessao", "lance"}


@pytest.mark.parametrize(
    ("visao", "excluir"),
    [
        # A sessao inteira se exclui (limpar dados de teste)...
        (SessaoView, True),
        # ...o lance avulso nao: deixaria os totais da sessao mentindo.
        (LanceView, False),
    ],
)
def test_sessao_e_lance_sao_registro_de_evento(visao, excluir):
    assert visao.can_create is False
    assert visao.can_edit is False
    assert visao.can_delete is excluir


def test_busca_da_sessao_por_uuid_sessao_e_id():
    assert set(SessaoView.column_searchable_list) == {Sessao.uuid_sessao, Sessao.id}


@pytest.fixture
def banco_com_fk():
    """SQLite com chaves estrangeiras LIGADAS (o padrao do SQLite e
    desligado, e ai a falha que o Postgres daria nao apareceria)."""
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(engine)
    Sessao_ = sessionmaker(bind=engine)
    db = Sessao_()
    # Insere sem FK (sem usuario/treino de verdade) e liga em seguida.
    db.execute(text("PRAGMA foreign_keys=OFF"))
    sessao = Sessao(
        uuid_sessao=uuid.uuid4(),
        usuario_id=1,
        treino_versao_id=1,
        iniciada_em=datetime(2026, 11, 5, tzinfo=timezone.utc),
    )
    db.add(sessao)
    db.flush()
    for bola in (1, 2):
        db.add(
            Lance(
                uuid_lance=uuid.uuid4(),
                sessao_id=sessao.id,
                bola=bola,
                resultado=TipoLance.acerto,
                ts_ms=bola * 1000,
            )
        )
    db.commit()
    db.execute(text("PRAGMA foreign_keys=ON"))
    yield db, sessao.id
    db.close()
    engine.dispose()


def _excluir_como_o_painel(db, sessao_id, com_gancho=True):
    """O que o sqladmin faz ao excluir: busca, on_model_delete, delete, commit."""
    obj = db.get(Sessao, sessao_id)
    if com_gancho:
        asyncio.run(SessaoView().on_model_delete(obj, None))
    db.delete(obj)
    db.commit()


def test_excluir_sessao_com_lances_falharia_sem_o_gancho(banco_com_fk):
    db, sessao_id = banco_com_fk
    with pytest.raises(IntegrityError):
        _excluir_como_o_painel(db, sessao_id, com_gancho=False)


def test_excluir_sessao_pelo_painel_leva_os_lances_junto(banco_com_fk):
    db, sessao_id = banco_com_fk

    _excluir_como_o_painel(db, sessao_id)

    assert db.get(Sessao, sessao_id) is None
    assert db.query(Lance).count() == 0
