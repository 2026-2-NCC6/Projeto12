from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import delete, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from src.core.auditoria import registrar_auditoria
from src.core.deps import usuario_atual
from src.core.security import conferir_senha, criar_token, gerar_hash
from src.db.session import get_db
from src.models.log_auditoria import LogAuditoria
from src.models.sessao import Lance, Sessao
from src.models.treino import Escopo, Treino, TreinoVersao
from src.models.usuario import Papel, Usuario
from src.schemas.auth import (
    CadastroEntrada,
    CalibracaoEntrada,
    EdicaoPerfilEntrada,
    ExclusaoContaEntrada,
    LoginEntrada,
    TokenSaida,
    UsuarioSaida,
)

router = APIRouter(prefix="/v1/auth", tags=["autenticacao"])

# Mesmo texto e mesmo 409 no cadastro e na edicao: o app trata os dois igual.
APELIDO_EM_USO = "Apelido ja em uso"


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


@router.post("/cadastro", response_model=UsuarioSaida, status_code=201)
def cadastrar(dados: CadastroEntrada, db: Session = Depends(get_db)):
    """Cria uma conta. O papel e sempre jogador: nunca vem do cliente."""
    if db.query(Usuario).filter(Usuario.email == dados.email).first():
        raise HTTPException(status_code=409, detail="E-mail ja cadastrado")

    if db.query(Usuario).filter(Usuario.apelido == dados.apelido).first():
        raise HTTPException(status_code=409, detail=APELIDO_EM_USO)

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


@router.put("/calibracao", response_model=UsuarioSaida)
def atualizar_calibracao(
    dados: CalibracaoEntrada,
    usuario: Usuario = Depends(usuario_atual),
    db: Session = Depends(get_db),
):
    """Atualiza o nivel de calibracao / dificuldade fisica do jogador.

    Marca `calibrado_em` a cada chamada, inclusive com calibracao 0: e um
    resultado legitimo (mediana de 38 graus ou menos), e sem a marca o app
    mandaria essa pessoa de volta para a calibracao toda vez.
    """
    usuario.calibracao = float(dados.calibracao)
    usuario.calibrado_em = datetime.now(timezone.utc)
    db.commit()
    db.refresh(usuario)
    return usuario


@router.patch("/eu", response_model=UsuarioSaida)
def editar_perfil(
    dados: EdicaoPerfilEntrada,
    request: Request,
    usuario: Usuario = Depends(usuario_atual),
    db: Session = Depends(get_db),
):
    """Troca o apelido de quem esta com o token (o unico campo editavel).

    Apelido de outra pessoa da o MESMO 409 do cadastro, para o app tratar
    os dois do mesmo jeito.
    """
    if dados.apelido == usuario.apelido:
        return usuario

    em_uso = db.query(Usuario).filter(
        Usuario.apelido == dados.apelido, Usuario.id != usuario.id
    ).first()
    if em_uso:
        raise HTTPException(status_code=409, detail=APELIDO_EM_USO)

    usuario.apelido = dados.apelido
    registrar_auditoria(db, usuario, "apelido_alterado", "usuario", usuario.id, _ip(request))
    try:
        db.commit()
    except IntegrityError:
        # Duas pessoas pegando o mesmo apelido ao mesmo tempo: o indice
        # unico barra a segunda, que recebe o mesmo 409.
        db.rollback()
        raise HTTPException(status_code=409, detail=APELIDO_EM_USO)
    db.refresh(usuario)
    return usuario


@router.delete("/eu", status_code=204)
def excluir_conta(
    dados: ExclusaoContaEntrada,
    request: Request,
    usuario: Usuario = Depends(usuario_atual),
    db: Session = Depends(get_db),
):
    """Exclui a conta de quem esta com o token. Definitivo, nao logico.

    Exige a senha: o token dura dias e nao pode ser revogado. Senha errada
    da o mesmo 401 do login.

    NUNCA falha por dependencia: so por senha errada ou falta de token. A
    pessoa nao pode ficar impedida de sair por algo que outro usuario fez.

    Uma regra so:
    - treino de que OUTRA pessoa depende (de catalogo, ou pessoal com sessao
      de outro usuario) perde o dono (owner_id nulo) e permanece, com as
      versoes: apaga-lo quebraria o historico de terceiros;
    - todo o resto da pessoa e apagado: sessoes, lances, treinos pessoais
      sem dependencia externa e suas versoes, e o usuario;
    - log_auditoria fica, com usuario_id anulado (o registro do que
      aconteceu sobrevive; o vinculo com a pessoa, nao).
    Copias de treinos dela feitas por outros continuam, so sem origem_id.

    Tudo numa transacao: ou apaga tudo, ou nada.
    """
    if not conferir_senha(dados.senha, usuario.senha_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciais invalidas",
        )

    uid = usuario.id
    # Os ids sao fixados ANTES de mexer em qualquer coisa: depois de orfanar,
    # um filtro por owner_id ja daria outro resultado no meio da transacao.
    meus = set(db.scalars(select(Treino.id).where(Treino.owner_id == uid)))
    usados_por_outros = set(
        db.scalars(
            select(TreinoVersao.treino_id)
            .join(Sessao, Sessao.treino_versao_id == TreinoVersao.id)
            .where(TreinoVersao.treino_id.in_(meus), Sessao.usuario_id != uid)
        )
    )
    # Catalogo inclui os apagados logicamente: continuam no banco justamente
    # porque ha historico apontando para eles.
    do_catalogo = set(
        db.scalars(
            select(Treino.id).where(Treino.id.in_(meus), Treino.escopo == Escopo.catalogo)
        )
    )
    orfanar = usados_por_outros | do_catalogo
    apagar = meus - orfanar

    minhas_sessoes = select(Sessao.id).where(Sessao.usuario_id == uid)

    # Ordem das chaves estrangeiras. Os lances sao apagados explicitamente,
    # e nao so pela cascata do banco: o SQLite dos testes nao aplica FK.
    db.execute(
        update(LogAuditoria).where(LogAuditoria.usuario_id == uid).values(usuario_id=None)
    )
    db.execute(delete(Lance).where(Lance.sessao_id.in_(minhas_sessoes)))
    db.execute(delete(Sessao).where(Sessao.usuario_id == uid))
    if apagar:
        # Treinos (de qualquer dono, inclusive os orfanados) copiados de um
        # que vai ser apagado perdem so o vinculo de origem.
        db.execute(
            update(Treino).where(Treino.origem_id.in_(apagar)).values(origem_id=None)
        )
        db.execute(delete(TreinoVersao).where(TreinoVersao.treino_id.in_(apagar)))
        db.execute(delete(Treino).where(Treino.id.in_(apagar)))
    if orfanar:
        db.execute(update(Treino).where(Treino.id.in_(orfanar)).values(owner_id=None))
        # Rastro para o admin achar o conteudo que ficou sem dono. O id do
        # treino nao e dado pessoal; o vinculo com a pessoa nao e guardado.
        for treino_id in sorted(orfanar):
            registrar_auditoria(
                db, None, "treino_orfanado", "treino", treino_id, _ip(request)
            )
    db.delete(usuario)
    # Sem usuario_id e sem entidade_id: registra que uma conta foi
    # excluida, sem guardar de quem.
    registrar_auditoria(db, None, "conta_excluida", "usuario", None, _ip(request))
    db.commit()
