from decimal import Decimal
from datetime import date

from pydantic import BaseModel, EmailStr, Field

from src.models.usuario import Perfil


class CadastroEntrada(BaseModel):
    """Dados que o aplicativo envia para criar uma conta."""

    email: EmailStr
    senha: str = Field(min_length=8, max_length=72)
    nome: str = Field(min_length=3, max_length=120)
    apelido: str = Field(min_length=2, max_length=40)
    data_nascimento: date
    perfil: Perfil = Perfil.casual


class LoginEntrada(BaseModel):
    email: EmailStr
    senha: str


class TokenSaida(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UsuarioSaida(BaseModel):
    """O que a API devolve sobre um usuario.

    A data de nascimento fica de fora: e guardada, mas nunca sai da API.
    """

    id: int
    email: str
    nome: str
    apelido: str
    perfil: Perfil
    papel: str
    calibracao: float = 0.0

    model_config = {"from_attributes": True}


class CalibracaoEntrada(BaseModel):
    """Nivel de calibracao / dificuldade em graus a ser adicionado aos limiares."""

    # Mesma validacao da `dificuldade` de SessaoEntrada: no maximo 1 casa.
    # Antes o servidor aceitava guardar aqui uma precisao que ele mesmo
    # recusava quando o valor voltava como dificuldade de uma sessao.
    calibracao: Decimal = Field(
        ge=0,
        le=45,
        decimal_places=1,
        description="Graus adicionais de dificuldade para acertos fortes no Tobias",
    )
