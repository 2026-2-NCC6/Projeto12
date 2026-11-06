"""Data no calendario de Sao Paulo, calculada pelo banco.

`data_sp(coluna)` vira, no SQL, a data local de um instante gravado em UTC.
Serve para contar "dias" como o jogador os vive: uma sessao as 22h em Sao
Paulo e 01h do dia seguinte em UTC, e contar em UTC poria metade dos treinos
noturnos no dia errado.

- Postgres (producao): `timezone('America/Sao_Paulo', col)`, com a base de
  fusos do proprio banco.
- SQLite (testes): nao tem base de fusos. Uma funcao Python registrada em
  cada conexao faz a conversao com `zoneinfo`.

Nada de deslocamento fixo de -3h: as regras de horario de verao mudam por
lei (o Brasil ja discutiu voltar com ele), e a base de fusos acompanha.
"""

import sqlite3
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import Date, event
from sqlalchemy.engine import Engine
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.sql.functions import FunctionElement

FUSO = "America/Sao_Paulo"
ZONA = ZoneInfo(FUSO)


class data_sp(FunctionElement):
    """Data (sem hora) em America/Sao_Paulo de uma coluna de instante."""

    type = Date()
    inherit_cache = True
    name = "data_sp"


@compiles(data_sp, "postgresql")
def _data_sp_postgres(elemento, compilador, **kw):
    (coluna,) = elemento.clauses
    return f"CAST(timezone('{FUSO}', {compilador.process(coluna, **kw)}) AS DATE)"


@compiles(data_sp, "sqlite")
def _data_sp_sqlite(elemento, compilador, **kw):
    (coluna,) = elemento.clauses
    return f"data_sp({compilador.process(coluna, **kw)})"


def _data_sp_python(valor):
    """O SQLite guarda o instante como texto em UTC, sem fuso (a ingestao
    converte tudo para UTC antes de gravar)."""
    if valor is None:
        return None
    instante = datetime.fromisoformat(valor)
    if instante.tzinfo is None:
        instante = instante.replace(tzinfo=timezone.utc)
    return instante.astimezone(ZONA).date().isoformat()


@event.listens_for(Engine, "connect")
def _registrar_no_sqlite(conexao_dbapi, _registro):
    if isinstance(conexao_dbapi, sqlite3.Connection):
        conexao_dbapi.create_function("data_sp", 1, _data_sp_python, deterministic=True)
