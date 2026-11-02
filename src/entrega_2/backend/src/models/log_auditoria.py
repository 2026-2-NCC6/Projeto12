from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column

from src.db.base import Base


class LogAuditoria(Base):
    __tablename__ = "log_auditoria"

    id: Mapped[int] = mapped_column(primary_key=True)
    usuario_id: Mapped[Optional[int]] = mapped_column(
        ForeignKey("usuario.id"), index=True
    )
    acao: Mapped[str] = mapped_column(String(60))
    entidade: Mapped[Optional[str]] = mapped_column(String(60))
    entidade_id: Mapped[Optional[str]] = mapped_column(String(60))
    ocorrido_em: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
    ip: Mapped[Optional[str]] = mapped_column(String(45))