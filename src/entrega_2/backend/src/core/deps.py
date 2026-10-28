from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from src.core.security import ler_token
from src.db.session import get_db
from src.models.usuario import Papel, Usuario

esquema = HTTPBearer()


def usuario_atual(
    credenciais: HTTPAuthorizationCredentials = Depends(esquema),
    db: Session = Depends(get_db),
) -> Usuario:
    try:
        payload = ler_token(credenciais.credentials)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido ou expirado",
        )

    usuario = db.get(Usuario, int(payload["sub"]))
    if usuario is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    return usuario


def exigir_admin(usuario: Usuario = Depends(usuario_atual)) -> Usuario:
    if usuario.papel != Papel.admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Requer papel de administrador",
        )
    return usuario