from typing import Optional

from sqlalchemy.orm import Session

from src.models.log_auditoria import LogAuditoria
from src.models.usuario import Usuario


def registrar_auditoria(
    db: Session,
    usuario: Optional[Usuario],
    acao: str,
    entidade: Optional[str] = None,
    entidade_id: Optional[object] = None,
    ip: Optional[str] = None,
) -> LogAuditoria:
    """Acrescenta um registro em log_auditoria. Base da US-707.

    Nao faz commit: o registro entra na transacao de quem chamou, para
    que a auditoria so exista se a operacao auditada tambem existir.
    Nunca passe dados pessoais em `acao` ou `entidade_id`.
    """
    registro = LogAuditoria(
        usuario_id=usuario.id if usuario is not None else None,
        acao=acao,
        entidade=entidade,
        entidade_id=str(entidade_id) if entidade_id is not None else None,
        ip=ip,
    )
    db.add(registro)
    return registro
