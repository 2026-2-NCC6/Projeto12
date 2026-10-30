from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from src.core.deps import exigir_admin
from src.db.session import get_db
from src.models.usuario import Usuario
from src.schemas.admin import PaginaUsuarios
from src.schemas.auth import UsuarioSaida

router = APIRouter(prefix="/v1/admin", tags=["administracao"])


@router.get("/usuarios", response_model=PaginaUsuarios)
def listar_usuarios(
    db: Session = Depends(get_db),
    _: Usuario = Depends(exigir_admin),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
):
    """Lista os usuarios cadastrados. Apenas para admin.

    A resposta usa o mesmo UsuarioSaida das outras rotas, entao CPF e
    data de nascimento continuam fora: nem o admin os ve pela API.
    """
    total = db.scalar(select(func.count()).select_from(Usuario))

    usuarios = db.scalars(
        select(Usuario).order_by(Usuario.id).limit(limit).offset(offset)
    ).all()

    return PaginaUsuarios(
        items=[UsuarioSaida.model_validate(u) for u in usuarios],
        total=total,
        limit=limit,
        offset=offset,
    )