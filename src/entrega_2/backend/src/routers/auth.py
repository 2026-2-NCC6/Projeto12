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
    """Cria uma conta. O papel e sempre jogador: nunca vem do cliente."""
    if db.query(Usuario).filter(Usuario.email == dados.email).first():
        raise HTTPException(status_code=409, detail="E-mail ja cadastrado")

    if db.query(Usuario).filter(Usuario.apelido == dados.apelido).first():
        raise HTTPException(status_code=409, detail="Apelido ja em uso")

    usuario = Usuario(
        email=dados.email,
        senha_hash=gerar_hash(dados.senha),
        nome=dados.nome,
        apelido=dados.apelido,
        data_nascimento=dados.data_nascimento,
        perfil=dados.perfil,
        papel=Papel.jogador,
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return usuario


@router.post("/login", response_model=TokenSaida)
def login(dados: LoginEntrada, db: Session = Depends(get_db)):
    """Confere as credenciais e devolve o token.

    A mensagem de erro e a mesma para e-mail inexistente e senha errada,
    para nao revelar quais e-mails estao cadastrados.
    """
    usuario = db.query(Usuario).filter(Usuario.email == dados.email).first()

    if usuario is None or not conferir_senha(dados.senha, usuario.senha_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciais invalidas",
        )

    token = criar_token(usuario.id, usuario.papel.value)
    return TokenSaida(access_token=token)


@router.get("/eu", response_model=UsuarioSaida)
def quem_sou_eu(usuario: Usuario = Depends(usuario_atual)):
    """Devolve os dados de quem esta com o token."""
    return usuario