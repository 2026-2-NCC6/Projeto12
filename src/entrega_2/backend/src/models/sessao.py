import enum
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import (
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Numeric,
    String,
    UniqueConstraint,
    func,
)
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
    sem_impacto = "sem_impacto"


class Sessao(Base):
    """Uma sessao de treino recebida do app.

    `id` e a identidade interna, gerada pelo servidor. `uuid_sessao` e a
    chave de idempotencia, gerada pelo app: unica por usuario, para que
    o mesmo UUID vindo de dois donos vire duas sessoes sem que um
    descubra o outro (US-704 / US-802).
    """

    __tablename__ = "sessao"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    uuid_sessao: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuario.id"))
    treino_versao_id: Mapped[int] = mapped_column(ForeignKey("treino_versao.id"))
    iniciada_em: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    encerrada_em: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    # Graus somados ao limiar de KO nesta sessao (terceiro parametro do
    # comando TREINO:qtd:intervalo:calib). E da sessao, nao do usuario:
    # usuario.calibracao pode mudar entre treinar e sincronizar.
    dificuldade: Mapped[Decimal] = mapped_column(
        Numeric(3, 1), default=Decimal("0"), server_default="0"
    )

    # Calculada pelo servidor (US-705); nula = ainda nao pontuada.
    # versao_pontuacao diz qual versao da regra gerou o valor.
    pontuacao_total: Mapped[Optional[int]] = mapped_column(default=None)
    versao_pontuacao: Mapped[Optional[int]] = mapped_column(default=None)

    # Agregados sempre recalculados pelo servidor a partir dos lances.
    acertos: Mapped[int] = mapped_column(default=0)
    erros: Mapped[int] = mapped_column(default=0)
    kos: Mapped[int] = mapped_column(default=0)
    melhor_sequencia: Mapped[int] = mapped_column(default=0)
    media_angulo: Mapped[Optional[float]] = mapped_column(Float)
    max_angulo: Mapped[Optional[float]] = mapped_column(Float)
    precisao: Mapped[Optional[float]] = mapped_column(Float)

    recebida_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    __table_args__ = (
        Index("ix_sessao_usuario_iniciada", "usuario_id", "iniciada_em"),
        UniqueConstraint("usuario_id", "uuid_sessao", name="uq_sessao_usuario_uuid"),
    )


class Lance(Base):
    __tablename__ = "lance"

    id: Mapped[int] = mapped_column(primary_key=True)

    # Chave de idempotencia do lance, gerada pelo app. Unica dentro da
    # sessao, e nao no banco todo, pelo mesmo motivo do uuid_sessao.
    uuid_lance: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))

    # Id gerado pelo ESP32 ("L-<millis>-<bola>"). So para rastrear contra
    # o log serial: millis() zera a cada boot, entao NAO e chave de nada.
    id_lance_firmware: Mapped[Optional[str]] = mapped_column(String(40))

    sessao_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("sessao.id"))
    bola: Mapped[int]
    resultado: Mapped[TipoLance] = mapped_column(Enum(TipoLance, name="tipo_lance"))
    # classe e knockout sao interpretacoes do firmware: guardadas como
    # vieram, mas a pontuacao nao as usa (recalcula o KO pelo angulo).
    knockout: Mapped[bool] = mapped_column(default=False)
    # Numeric e nao Float: a pontuacao converte para decimos de forma exata.
    angulo: Mapped[Optional[Decimal]] = mapped_column(Numeric(4, 1))
    classe: Mapped[Optional[ClasseImpacto]] = mapped_column(
        Enum(ClasseImpacto, name="classe_impacto")
    )
    ts_ms: Mapped[int]
    pontos: Mapped[int] = mapped_column(default=0)

    __table_args__ = (
        Index("ix_lance_sessao_ts", "sessao_id", "ts_ms"),
        UniqueConstraint("sessao_id", "uuid_lance", name="uq_lance_sessao_uuid"),
    )
