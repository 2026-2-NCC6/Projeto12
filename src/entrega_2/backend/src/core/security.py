from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from src.core.config import settings

ALGORITMO = "HS256"


def gerar_hash(senha: str) -> str:
    return bcrypt.hashpw(senha.encode(), bcrypt.gensalt()).decode()


def conferir_senha(senha: str, hash_salvo: str) -> bool:
    return bcrypt.checkpw(senha.encode(), hash_salvo.encode())


def criar_token(usuario_id: int, papel: str) -> str:
    expira_em = datetime.now(timezone.utc) + timedelta(
        minutes=settings.jwt_expire_minutes
    )
    payload = {"sub": str(usuario_id), "papel": papel, "exp": expira_em}
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITMO)


def ler_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITMO])