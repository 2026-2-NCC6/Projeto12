from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from src.core.deps import usuario_atual
from src.core.security import conferir_senha, criar_token, gerar_hash
from src.db.session import get_db
from src.models.usuario import Papel, Usuario
from src.schemas.auth import CadastroEntrada, LoginEntrada, TokenSaida, UsuarioSaida

router = APIRouter(prefix="/v1/auth", tags=["autenticacao"])


@router.post("/cadastro", response_model=UsuarioSaida, status_code=201)
def cadastrar(dados: CadastroEntrada, db: Session = Depends(get_db)):
    ja_existe = db.query(Usuario).filter(Usuario.email == dados.email).first()
    if ja_existe:
        raise HTTPException(status_code=409, detail="E-mail ja cadastrado")

    usuario = Usuario(
        email=dados.email,
        senha_hash=gerar_hash(dados.senha),
        papel=Papel.jogador,
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return usuario


@router.post("/login", response_model=TokenSaida)
def login(dados: LoginEntrada, db: Session = Depends(get_db)):
    usuario = db.query(Usuario).filter(Usuario.email == dados.email).first()

    if usuario is None or not conferir_senha(dados.senha, usuario.senha_hash):
        raise HTTPException(status_code=401, detail="Credenciais invalidas")

    token = criar_token(usuario.id, usuario.papel.value)
    return TokenSaida(access_token=token)


@router.get("/eu", response_model=UsuarioSaida)
def quem_sou_eu(usuario: Usuario = Depends(usuario_atual)):
    return usuario