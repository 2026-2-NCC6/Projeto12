import enum
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Enum, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column

from src.db.base import Base


class Escopo(str, enum.Enum):
    catalogo = "catalogo"
    pessoal = "pessoal"


class Nivel(str, enum.Enum):
    facil = "facil"
    medio = "medio"
    dificil = "dificil"
    infantil = "infantil"
    personalizado = "personalizado"


class Treino(Base):
    __tablename__ = "treino"

    id: Mapped[int] = mapped_column(primary_key=True)
    titulo: Mapped[str] = mapped_column(String(120))
    descricao: Mapped[Optional[str]] = mapped_column(String(500))
    escopo: Mapped[Escopo] = mapped_column(Enum(Escopo, name="escopo_treino"))
    owner_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("usuario.id"), index=True
    )
    origem_id: Mapped[Optional[int]] = mapped_column(ForeignKey("treino.id"))
    criado_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class TreinoVersao(Base):
    __tablename__ = "treino_versao"

    id: Mapped[int] = mapped_column(primary_key=True)
    treino_id: Mapped[int] = mapped_column(ForeignKey("treino.id"), index=True)
    numero: Mapped[int]
    nivel: Mapped[Nivel] = mapped_column(Enum(Nivel, name="nivel_treino"))
    qtd_lances: Mapped[int]
    intervalo_ms: Mapped[int]
    falas_tobias: Mapped[bool] = mapped_column(default=True)
    publicado_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )