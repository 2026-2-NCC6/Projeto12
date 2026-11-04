import logging

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from src.core.auditoria import registrar_auditoria
from src.core.deps import usuario_atual
from src.core.totais_sessao import recalcular_totais
from src.db.session import get_db
from src.models.sessao import Lance, Sessao
from src.models.treino import Treino, TreinoVersao
from src.models.usuario import Usuario
from src.routers.treinos import acessivel_para_ingestao
from src.schemas.sessao import LoteEntrada, LoteSaida, ResumoSessaoSaida, SessaoEntrada

router = APIRouter(prefix="/v1/sessions", tags=["sessoes"])

logger = logging.getLogger("tobias.pontuacao")


def versoes_aceitas(db: Session, usuario: Usuario, ids: set[int]) -> set[int]:
    """Das versoes pedidas no lote, quais este usuario pode usar.

    Uma query so para o lote inteiro. Versao inexistente e versao de
    outro dono caem no mesmo lugar: fora do conjunto.
    """
    return set(
        db.scalars(
            select(TreinoVersao.id)
            .join(Treino, Treino.id == TreinoVersao.treino_id)
            .where(TreinoVersao.id.in_(ids), acessivel_para_ingestao(usuario))
        ).all()
    )


def comparar_com_cliente(
    db: Session,
    usuario: Usuario,
    sessao: Sessao,
    dados: SessaoEntrada,
    lances_gravados: list[Lance],
    ip: str | None,
) -> None:
    """Alerta se o placar do app diverge do oficial (US-705 / RF23).

    So compara quando os lances do payload cobrem todos os gravados: numa
    sincronizacao parcial o app esta pontuando outro conjunto de lances e
    a diferenca nao significaria nada. Quem chama garante a outra guarda
    (a requisicao mudou algo), para um reenvio nao repetir o alerta.
    """
    if dados.pontuacao_cliente is None:
        return

    enviados = {l.uuid_lance for l in dados.lances}
    if not {l.uuid_lance for l in lances_gravados} <= enviados:
        return

    if dados.pontuacao_cliente == sessao.pontuacao_total:
        return

    # Sem dados pessoais: so ids internos e numeros.
    logger.warning(
        "pontuacao_divergente sessao_id=%s usuario_id=%s pontuacao_servidor=%s "
        "pontuacao_cliente=%s versao_regra=%s",
        sessao.id,
        usuario.id,
        sessao.pontuacao_total,
        dados.pontuacao_cliente,
        sessao.versao_pontuacao,
        extra={
            "evento": "pontuacao_divergente",
            "sessao_id": str(sessao.id),
            "usuario_id": usuario.id,
            "pontuacao_servidor": sessao.pontuacao_total,
            "pontuacao_cliente": dados.pontuacao_cliente,
            "versao_regra": sessao.versao_pontuacao,
        },
    )
    registrar_auditoria(db, usuario, "pontuacao_divergente", "sessao", sessao.id, ip)


def ingerir_sessao(
    db: Session,
    usuario: Usuario,
    dados: SessaoEntrada,
    versoes_ok: set[int],
    ip: str | None,
) -> ResumoSessaoSaida:
    """Grava uma sessao do lote, sem duplicar nada.

    - sessao: cria se nao existe para este usuario; se existe, a primeira
      gravacao vence e so encerrada_em e preenchida, se ainda nula;
    - lances: insere so os uuid_lance que a sessao ainda nao tem;
    - totais e pontuacao: recalculados sempre que algo mudou, e so entao
      o placar do app e comparado com o oficial.
    """
    recebidos = len(dados.lances)

    sessao = db.scalars(
        select(Sessao).where(
            Sessao.usuario_id == usuario.id,
            Sessao.uuid_sessao == dados.uuid_sessao,
        )
    ).first()

    mudou = False
    if sessao is None:
        # A versao so e conferida na criacao: numa sessao que ja existe
        # ela e campo imutavel, e o valor enviado agora e ignorado.
        if dados.treino_versao_id not in versoes_ok:
            registrar_auditoria(db, usuario, "sessao_rejeitada", "sessao", None, ip)
            return ResumoSessaoSaida(
                uuid_sessao=dados.uuid_sessao,
                situacao="rejeitada",
                motivo="versao_invalida",
                lances_recebidos=recebidos,
                lances_inseridos=0,
                lances_duplicados=0,
            )

        sessao = Sessao(
            uuid_sessao=dados.uuid_sessao,
            usuario_id=usuario.id,
            treino_versao_id=dados.treino_versao_id,
            iniciada_em=dados.iniciada_em,
            encerrada_em=dados.encerrada_em,
            dificuldade=dados.dificuldade,
        )
        db.add(sessao)
        db.flush()
        situacao = "inserida"
    else:
        situacao = "ja_existia"
        if sessao.encerrada_em is None and dados.encerrada_em is not None:
            sessao.encerrada_em = dados.encerrada_em
            mudou = True

    # Uma query para saber o que a sessao ja tem. `ja_vistos` tambem
    # absorve UUID repetido dentro do proprio payload.
    ja_vistos = set(
        db.scalars(
            select(Lance.uuid_lance).where(
                Lance.sessao_id == sessao.id,
                Lance.uuid_lance.in_([l.uuid_lance for l in dados.lances]),
            )
        ).all()
    ) if dados.lances else set()

    novos = []
    for l in dados.lances:
        if l.uuid_lance in ja_vistos:
            continue
        ja_vistos.add(l.uuid_lance)
        novos.append(
            Lance(
                sessao_id=sessao.id,
                uuid_lance=l.uuid_lance,
                id_lance_firmware=l.id_lance_firmware,
                bola=l.bola,
                resultado=l.resultado,
                classe=l.classe,
                knockout=l.knockout,
                angulo=l.angulo,
                ts_ms=l.ts_ms,
            )
        )
    db.add_all(novos)
    db.flush()

    if situacao == "inserida" or novos or mudou:
        gravados = recalcular_totais(db, sessao)
        acao = "sessao_inserida" if situacao == "inserida" else "sessao_atualizada"
        registrar_auditoria(db, usuario, acao, "sessao", sessao.id, ip)
        comparar_com_cliente(db, usuario, sessao, dados, gravados, ip)
        db.flush()

    return ResumoSessaoSaida(
        uuid_sessao=dados.uuid_sessao,
        situacao=situacao,
        lances_recebidos=recebidos,
        lances_inseridos=len(novos),
        lances_duplicados=recebidos - len(novos),
        pontuacao_total=sessao.pontuacao_total,
    )


def ingerir_com_savepoint(
    db: Session,
    usuario: Usuario,
    dados: SessaoEntrada,
    versoes_ok: set[int],
    ip: str | None,
) -> ResumoSessaoSaida:
    """Cada sessao num savepoint proprio.

    Se o mesmo lote chega duas vezes ao mesmo tempo, o indice unico
    barra a segunda gravacao com IntegrityError. Desfaz so esta sessao
    e tenta de novo: agora ela ja existe e cai em "ja_existia", sem
    derrubar as outras sessoes do lote.
    """
    for tentativa in (1, 2):
        try:
            with db.begin_nested():
                return ingerir_sessao(db, usuario, dados, versoes_ok, ip)
        except IntegrityError:
            if tentativa == 2:
                raise


@router.post("", response_model=LoteSaida, status_code=200)
def ingerir(
    lote: LoteEntrada,
    request: Request,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
):
    """Recebe um lote de sessoes do app (US-704 / RF19), de forma idempotente.

    Reenviar o mesmo lote nao duplica nada. O codigo HTTP descreve o
    lote: e sempre 200, e o resultado de cada sessao vem em `situacao`.
    422 so para payload malformado, antes de qualquer acesso ao banco.
    O dono das sessoes e quem esta com o token, nunca o corpo.
    """
    ip = request.client.host if request.client else None
    versoes_ok = versoes_aceitas(
        db, usuario, {s.treino_versao_id for s in lote.sessoes}
    )

    resumos = [
        ingerir_com_savepoint(db, usuario, dados, versoes_ok, ip)
        for dados in lote.sessoes
    ]
    db.commit()
    return LoteSaida(sessoes=resumos)
