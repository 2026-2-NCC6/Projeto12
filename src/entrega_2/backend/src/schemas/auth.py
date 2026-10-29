from datetime import date

from pydantic import BaseModel, EmailStr, Field, field_validator

from src.models.usuario import Perfil


class CadastroEntrada(BaseModel):
    """Dados que o aplicativo envia para criar uma conta."""

    email: EmailStr
    senha: str = Field(min_length=8, max_length=72)
    nome: str = Field(min_length=3, max_length=120)
    apelido: str = Field(min_length=2, max_length=40)
    cpf: str
    data_nascimento: date
    perfil: Perfil = Perfil.casual

    @field_validator("cpf")
    @classmethod
    def validar_cpf(cls, valor: str) -> str:
        """Remove a formatacao e confere os digitos verificadores."""
        digitos = "".join(c for c in valor if c.isdigit())

        if len(digitos) != 11 or digitos == digitos[0] * 11:
            raise ValueError("CPF invalido")

        for posicao in (9, 10):
            soma = sum(
                int(digitos[i]) * (posicao + 1 - i) for i in range(posicao)
            )
            resto = (soma * 10) % 11 % 10
            if resto != int(digitos[posicao]):
                raise ValueError("CPF invalido")

        return digitos


class LoginEntrada(BaseModel):
    email: EmailStr
    senha: str


class TokenSaida(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UsuarioSaida(BaseModel):
    """O que a API devolve sobre um usuario.

    CPF e data de nascimento ficam de fora de proposito: sao guardados,
    mas nunca saem da API.
    """

    id: int
    email: str
    nome: str
    apelido: str
    perfil: Perfil
    papel: str

    model_config = {"from_attributes": True}