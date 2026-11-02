from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from src.core.deps import usuario_atual
from src.db.session import get_db
from src.models.treino import Escopo, Nivel, Treino, TreinoVersao
from src.models.usuario import Papel, Usuario
from src.schemas.treino import (
    PaginaTreinos,
    TreinoEntrada,
    TreinoSaida,
    VersaoSaida,
)

router = APIRouter(prefix="/v1/drills", tags=["treinos"])


def visiveis_para(usuario: Usuario):
    """Treinos que este usuario pode ver.

    Exclui os apagados sempre: a exclusao e logica, a linha continua
    no banco para que o historico de sessoes nao quebre.
    """
    nao_apagado = Treino.apagado_em.is_(None)

    if usuario.papel == Papel.admin:
        return nao_apagado

    return and_(
        nao_apagado,
        or_(
            Treino.escopo == Escopo.catalogo,
            Treino.owner_id == usuario.id,
        ),
    )


def versao_atual(db: Session, treino_id: int) -> TreinoVersao | None:
    """A versao de maior numero daquele treino."""
    return db.scalars(
        select(TreinoVersao)
        .where(TreinoVersao.treino_id == treino_id)
        .order_by(TreinoVersao.numero.desc())
        .limit(1)
    ).first()


def buscar_visivel(db: Session, treino_id: int, usuario: Usuario) -> Treino:
    """Busca um treino aplicando a regra de acesso na mesma consulta.

    Nunca buscar so por id: perguntar 'existe E e visivel para esta
    pessoa' de uma vez e o que previne o IDOR da US-802.
    """
    treino = db.scalars(
        select(Treino).where(Treino.id == treino_id, visiveis_para(usuario))
    ).first()

    if treino is None:
        raise HTTPException(status_code=404, detail="Treino nao encontrado")

    return treino


@router.get("", response_model=PaginaTreinos)
def listar(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
    escopo: Escopo | None = None,
    nivel: Nivel | None = None,
    busca: str | None = None,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
):
    """Lista treinos com paginacao e filtros.

    O jogador ve apenas o catalogo e os proprios treinos, qualquer
    que seja o filtro que ele mande.
    """
    condicoes = [visiveis_para(usuario)]

    if escopo is not None:
        condicoes.append(Treino.escopo == escopo)

    if busca:
        condicoes.append(Treino.titulo.ilike(f"%{busca}%"))

    if nivel is not None:
        condicoes.append(
            Treino.id.in_(
                select(TreinoVersao.treino_id).where(TreinoVersao.nivel == nivel)
            )
        )

    total = db.scalar(
        select(func.count()).select_from(Treino).where(*condicoes)
    )

    treinos = db.scalars(
        select(Treino)
        .where(*condicoes)
        .order_by(Treino.titulo)
        .limit(limit)
        .offset(offset)
    ).all()

    items = []
    for treino in treinos:
        saida = TreinoSaida.model_validate(treino)
        versao = versao_atual(db, treino.id)
        if versao is not None:
            saida.versao_atual = VersaoSaida.model_validate(versao)
        items.append(saida)

    return PaginaTreinos(items=items, total=total, limit=limit, offset=offset)


@router.post("", response_model=TreinoSaida, status_code=201)
def criar(
    dados: TreinoEntrada,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
):
    """Cria um treino com a primeira versao.

    O escopo e derivado do papel: admin publica no catalogo, jogador
    cria apenas treinos pessoais. Nunca vem do cliente.
    """
    if usuario.papel == Papel.admin:
        escopo = Escopo.catalogo
        owner_id = None
    else:
        escopo = Escopo.pessoal
        owner_id = usuario.id

    treino = Treino(
        titulo=dados.titulo,
        descricao=dados.descricao,
        escopo=escopo,
        owner_id=owner_id,
        origem_id=None,
    )
    db.add(treino)
    db.flush()

    versao = TreinoVersao(
        treino_id=treino.id,
        numero=1,
        nivel=dados.nivel,
        qtd_lances=dados.qtd_lances,
        intervalo_ms=dados.intervalo_ms,
        falas_tobias=dados.falas_tobias,
    )
    db.add(versao)
    db.commit()
    db.refresh(treino)

    saida = TreinoSaida.model_validate(treino)
    saida.versao_atual = VersaoSaida.model_validate(versao)
    return saida


@router.get("/{treino_id}", response_model=TreinoSaida)
def detalhar(
    treino_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
):
    """Detalhe de um treino, com a versao atual.

    Devolve 404 quando o treino existe mas nao e deste usuario: nao
    revelar a existencia e parte da prevencao de IDOR da US-802.
    """
    treino = buscar_visivel(db, treino_id, usuario)

    saida = TreinoSaida.model_validate(treino)
    versao = versao_atual(db, treino.id)
    if versao is not None:
        saida.versao_atual = VersaoSaida.model_validate(versao)
    return saida


@router.get("/{treino_id}/versions", response_model=list[VersaoSaida])
def listar_versoes(
    treino_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
):
    """Historico de versoes do treino, da mais nova para a mais antiga."""
    buscar_visivel(db, treino_id, usuario)

    return db.scalars(
        select(TreinoVersao)
        .where(TreinoVersao.treino_id == treino_id)
        .order_by(TreinoVersao.numero.desc())
    ).all()


@router.post("/{treino_id}/copy", response_model=TreinoSaida, status_code=201)
def copiar(
    treino_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
):
    """Copia um treino para os treinos pessoais de quem chamou.

    Copy-on-write da US-609: o original nao e alterado, e a copia
    guarda em origem_id de onde veio.
    """
    original = buscar_visivel(db, treino_id, usuario)

    versao_origem = versao_atual(db, original.id)
    if versao_origem is None:
        raise HTTPException(
            status_code=409, detail="Treino sem versao publicada"
        )

    copia = Treino(
        titulo=f"{original.titulo} (minha)",
        descricao=original.descricao,
        escopo=Escopo.pessoal,
        owner_id=usuario.id,
        origem_id=original.id,
    )
    db.add(copia)
    db.flush()

    nova_versao = TreinoVersao(
        treino_id=copia.id,
        numero=1,
        nivel=versao_origem.nivel,
        qtd_lances=versao_origem.qtd_lances,
        intervalo_ms=versao_origem.intervalo_ms,
        falas_tobias=versao_origem.falas_tobias,
    )
    db.add(nova_versao)
    db.commit()
    db.refresh(copia)

    saida = TreinoSaida.model_validate(copia)
    saida.versao_atual = VersaoSaida.model_validate(nova_versao)
    return saida


@router.put("/{treino_id}", response_model=TreinoSaida)
def editar(
    treino_id: int,
    dados: TreinoEntrada,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
):
    """Edita um treino publicando uma versao nova.

    A versao anterior nao e alterada: as sessoes ja realizadas
    continuam apontando para ela, e o historico permanece correto.
    """
    treino = buscar_visivel(db, treino_id, usuario)

    if usuario.papel != Papel.admin and treino.owner_id != usuario.id:
        raise HTTPException(status_code=404, detail="Treino nao encontrado")

    treino.titulo = dados.titulo
    treino.descricao = dados.descricao

    anterior = versao_atual(db, treino.id)
    proximo_numero = (anterior.numero + 1) if anterior else 1

    nova_versao = TreinoVersao(
        treino_id=treino.id,
        numero=proximo_numero,
        nivel=dados.nivel,
        qtd_lances=dados.qtd_lances,
        intervalo_ms=dados.intervalo_ms,
        falas_tobias=dados.falas_tobias,
    )
    db.add(nova_versao)
    db.commit()
    db.refresh(treino)

    saida = TreinoSaida.model_validate(treino)
    saida.versao_atual = VersaoSaida.model_validate(nova_versao)
    return saida


@router.delete("/{treino_id}", status_code=204)
def excluir(
    treino_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
):
    """Exclusao logica de um treino.

    O jogador apaga apenas os proprios treinos pessoais. O admin
    apaga qualquer treino, inclusive do catalogo. A linha permanece
    no banco porque as sessoes apontam para as versoes do treino.
    """
    treino = buscar_visivel(db, treino_id, usuario)

    if usuario.papel == Papel.admin:
        pass
    elif treino.escopo == Escopo.catalogo:
        raise HTTPException(
            status_code=403,
            detail="Treinos do catalogo nao podem ser excluidos",
        )
    elif treino.owner_id != usuario.id:
        raise HTTPException(status_code=404, detail="Treino nao encontrado")

    treino.apagado_em = datetime.now(timezone.utc)
    db.commit()