from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from src.models.treino import Escopo, Nivel


class VersaoSaida(BaseModel):
    """Os parametros de um treino em uma versao."""

    numero: int
    nivel: Nivel
    qtd_lances: int
    intervalo_ms: int
    falas_tobias: bool
    publicado_em: datetime

    model_config = {"from_attributes": True}


class TreinoSaida(BaseModel):
    id: int
    titulo: str
    descricao: Optional[str]
    escopo: Escopo
    owner_id: Optional[int]
    origem_id: Optional[int]
    versao_atual: Optional[VersaoSaida] = None

    model_config = {"from_attributes": True}


class PaginaTreinos(BaseModel):
    """Envelope de paginacao: o app precisa do total para saber se ha proxima pagina."""

    items: list[TreinoSaida]
    total: int
    limit: int
    offset: int


class TreinoEntrada(BaseModel):
    """O que o cliente pode enviar ao criar um treino.

    Nao existe campo escopo nem owner_id de proposito: ambos sao
    derivados de quem esta chamando, nunca do corpo da requisicao.
    """

    titulo: str = Field(min_length=3, max_length=120)
    descricao: Optional[str] = Field(default=None, max_length=500)
    nivel: Nivel
    qtd_lances: int = Field(ge=1, le=200)
    intervalo_ms: int = Field(ge=500, le=60000)
    falas_tobias: bool = True