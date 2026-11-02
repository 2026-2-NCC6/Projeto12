import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Enum, Float, ForeignKey, Index, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from src.db.base import Base


class TipoLance(str, enum.Enum):
    acerto = "acerto"
    erro = "erro"


class ClasseImpacto(str, enum.Enum):
    fraco = "fraco"
    medio = "medio"
    forte = "forte"


class Sessao(Base):
    __tablename__ = "sessao"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuario.id"))
    treino_versao_id: Mapped[int] = mapped_column(ForeignKey("treino_versao.id"))
    iniciada_em: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    encerrada_em: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    pontuacao_total: Mapped[int] = mapped_column(default=0)
    acertos: Mapped[int] = mapped_column(default=0)
    erros: Mapped[int] = mapped_column(default=0)
    kos: Mapped[int] = mapped_column(default=0)
    melhor_sequencia: Mapped[int] = mapped_column(default=0)
    recebida_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (Index("ix_sessao_usuario_iniciada", "usuario_id", "iniciada_em"),)


class Lance(Base):
    __tablename__ = "lance"

    id: Mapped[int] = mapped_column(primary_key=True)
    uuid_lance: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), unique=True)
    sessao_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("sessao.id"))
    numero: Mapped[int]
    tipo: Mapped[TipoLance] = mapped_column(Enum(TipoLance, name="tipo_lance"))
    knockout: Mapped[bool] = mapped_column(default=False)
    intensidade: Mapped[Optional[float]] = mapped_column(Float)
    classe: Mapped[Optional[ClasseImpacto]] = mapped_column(
        Enum(ClasseImpacto, name="classe_impacto")
    )
    ts_ms: Mapped[int]
    pontos: Mapped[int] = mapped_column(default=0)

    __table_args__ = (Index("ix_lance_sessao_ts", "sessao_id", "ts_ms"),)