from pydantic import BaseModel, EmailStr, Field


class CadastroEntrada(BaseModel):
    email: EmailStr
    senha: str = Field(
        min_length=8,
        max_length=72,
        description="Senha com no mínimo 8 caracteres",
    )


class LoginEntrada(BaseModel):
    email: EmailStr
    senha: str


class TokenSaida(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UsuarioSaida(BaseModel):
    id: int
    email: str
    papel: str

    model_config = {"from_attributes": True}