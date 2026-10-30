from pydantic import BaseModel

from src.schemas.auth import UsuarioSaida


class PaginaUsuarios(BaseModel):
    items: list[UsuarioSaida]
    total: int
    limit: int
    offset: int