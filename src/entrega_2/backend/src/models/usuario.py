import enum
from datetime import date, datetime
from typing import Optional

from sqlalchemy import Date, DateTime, Enum, Float, String, func
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
    calibracao: Mapped[float] = mapped_column(
        Float, default=0.0, server_default="0.0"
    )
    # Quando a calibracao foi feita; nulo = nunca calibrou. O valor da
    # calibracao NAO serve de marca: a formula e clamp(mediana - 38, 0, 20),
    # entao quem bate com mediana de 38 graus ou menos calibra de verdade e
    # recebe 0, igual a quem nunca calibrou.
    calibrado_em: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    criado_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
