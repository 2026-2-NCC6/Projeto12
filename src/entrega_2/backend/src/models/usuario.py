import enum
from datetime import date, datetime

from sqlalchemy import Date, DateTime, Enum, String, func
from sqlalchemy.orm import Mapped, mapped_column

from src.db.base import Base


class Papel(str, enum.Enum):
    jogador = "jogador"
    admin = "admin"


class Perfil(str, enum.Enum):
    casual = "casual"
    iniciante = "iniciante"
    infantil = "infantil"


class Usuario(Base):
    __tablename__ = "usuario"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    senha_hash: Mapped[str] = mapped_column(String(255))
    nome: Mapped[str] = mapped_column(String(120))
    apelido: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    data_nascimento: Mapped[date] = mapped_column(Date)
    perfil: Mapped[Perfil] = mapped_column(
        Enum(Perfil, name="perfil_jogador"), default=Perfil.casual
    )
    papel: Mapped[Papel] = mapped_column(
        Enum(Papel, name="papel_usuario"), default=Papel.jogador
    )
    criado_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )