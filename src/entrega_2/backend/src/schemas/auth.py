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

    model_config = {"from_attributes": True}