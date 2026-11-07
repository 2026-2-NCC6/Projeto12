from datetime import date, datetime
from decimal import Decimal
from typing import Annotated

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from src.models.usuario import Perfil

# A mesma regra no cadastro e na edicao: um apelido valido num lugar e
# recusado no outro seria um bug esperando para acontecer.
Apelido = Annotated[str, Field(min_length=2, max_length=40)]


class CadastroEntrada(BaseModel):
    """Dados que o aplicativo envia para criar uma conta."""

    email: EmailStr
    senha: str = Field(min_length=8, max_length=72)
    nome: str = Field(min_length=3, max_length=120)
    apelido: Apelido
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
    # Nulo = nunca calibrou. E isto, e nao `calibracao == 0`, que diz se a
    # pessoa precisa passar pela calibracao (0 e um resultado legitimo).
    calibrado_em: datetime | None = None

    model_config = {"from_attributes": True}


class EdicaoPerfilEntrada(BaseModel):
    """PATCH /v1/auth/eu: so o apelido.

    Nome e e-mail nao sao editaveis (o e-mail e a identidade de login, e
    muda-lo exigiria verificacao). Campo a mais e 422, e nao ignorado em
    silencio: quem mandar `email` precisa saber que nada mudou.
    """

    model_config = ConfigDict(extra="forbid")

    apelido: Apelido


class ExclusaoContaEntrada(BaseModel):
    """DELETE /v1/auth/eu exige a senha: o token dura dias e nao pode ser
    revogado, entao uma operacao destrutiva pede reautenticacao."""

    senha: str


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
