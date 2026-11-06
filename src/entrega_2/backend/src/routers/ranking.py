"""GET /v1/ranking: classificacao entre jogadores.

E a PRIMEIRA rota que mostra dados de um usuario a outro (GET /v1/sessions
devolve so as proprias sessoes, de proposito). As regras de privacidade
abaixo sao decisao de produto, nao detalhe de implementacao: antes de
"simplificar" qualquer uma, leia o porque.

PRIVACIDADE 1 - So o apelido. Nunca e-mail, nome ou id. O apelido ja e
    unico, entao basta para o ranking; o resto identificaria a pessoa fora
    do app (e o id deixaria correlacionar com outras rotas e logs).
    O schema de saida (ItemRanking) so tem apelido, valor, posicao e sessoes.

PRIVACIDADE 2 - Menores de idade ficam fora da lista, pela data de
    nascimento no dia de hoje em Sao Paulo. Quem nao tem data preenchida
    tambem fica fora: na duvida, nao exponha. (Hoje a coluna e NOT NULL, mas
    a regra nao pode depender disso continuar assim.)

PRIVACIDADE 3 - Quem esta fora da lista CONTINUA vendo a propria posicao em
    `voce`, calculada contra a mesma lista publica. Ficar fora significa nao
    aparecer para os outros, nao perder a funcionalidade. `voce.oculto` diz
    a pessoa se ela esta fora por esta regra (e nao so abaixo do corte dos
    20): e informacao sobre si mesma, nunca sobre terceiros.

Limitacao conhecida: um adulto nao tem como optar por ficar fora. A versao
completa teria uma preferencia no perfil (registrado na issue).

Agregacao no banco (GROUP BY sobre sessao), nunca carregando as sessoes para
somar em Python.
"""

from datetime import date, datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import Float, and_, case, cast, func, or_, select
from sqlalchemy.orm import Session

from src.core.deps import usuario_atual
from src.db.data_local import ZONA, data_sp
from src.db.session import get_db
from src.models.sessao import Sessao
from src.models.usuario import Usuario
from src.schemas.ranking import (
    ItemRanking,
    Metrica,
    Periodo,
    RankingSaida,
    VoceRanking,
)

router = APIRouter(prefix="/v1/ranking", tags=["ranking"])

TAMANHO_LISTA = 20
MAIORIDADE = 18

# Evolucao: minimo de sessoes em CADA um dos dois periodos. Sem piso, quem
# treinou uma vez no mes passado e duas neste aparece com +100% e lidera.
# Quem nao atinge o minimo fica FORA da metrica (nao entra com zero).
MINIMO_SESSOES_EVOLUCAO = 3


def agora() -> datetime:
    """Relogio da rota; os testes o trocam por um instante fixo."""
    return datetime.now(timezone.utc)


def _corte_maioridade(hoje: date) -> date:
    """Nascidos ate esta data ja tem 18 anos hoje.

    Quem nasceu em 29/02 so entra a partir de 01/03 nos anos nao bissextos:
    na duvida, o dia mais tarde.
    """
    try:
        return hoje.replace(year=hoje.year - MAIORIDADE)
    except ValueError:  # hoje e 29/02 e o ano de corte nao e bissexto
        return date(hoje.year - MAIORIDADE, 2, 28)


def _aparece_para_os_outros(hoje: date):
    """PRIVACIDADE 2: adultos com data de nascimento conhecida."""
    return and_(
        Usuario.data_nascimento.is_not(None),
        Usuario.data_nascimento <= _corte_maioridade(hoje),
    )


def _agregado(metrica: Metrica, ref: datetime):
    """Subquery (usuario_id, valor, sessoes) da metrica, e o periodo dela."""
    if metrica == "pontos":
        de = ref - timedelta(days=30)
        sub = (
            select(
                Sessao.usuario_id,
                func.sum(Sessao.pontuacao_total).label("valor"),
                func.count().label("sessoes"),
            )
            .where(
                Sessao.iniciada_em >= de,
                Sessao.iniciada_em <= ref,
                Sessao.pontuacao_total.is_not(None),
            )
            .group_by(Sessao.usuario_id)
        )
        return sub.subquery(), Periodo(de=de, ate=ref)

    if metrica == "frequencia":
        # Os 7 dias de calendario de Sao Paulo terminados hoje, contando a
        # partir da meia-noite LOCAL de 6 dias atras.
        hoje = ref.astimezone(ZONA).date()
        de = datetime.combine(hoje - timedelta(days=6), time(), ZONA).astimezone(
            timezone.utc
        )
        sub = (
            select(
                Sessao.usuario_id,
                func.count(func.distinct(data_sp(Sessao.iniciada_em))).label("valor"),
                func.count().label("sessoes"),
            )
            .where(Sessao.iniciada_em >= de, Sessao.iniciada_em <= ref)
            .group_by(Sessao.usuario_id)
        )
        return sub.subquery(), Periodo(de=de, ate=ref)

    # evolucao: 30 dias contra os 30 anteriores.
    meio = ref - timedelta(days=30)
    inicio = ref - timedelta(days=60)
    no_atual = Sessao.iniciada_em >= meio
    pontos_atual = func.sum(case((no_atual, Sessao.pontuacao_total), else_=0))
    pontos_anterior = func.sum(case((no_atual, 0), else_=Sessao.pontuacao_total))
    n_atual = func.count(case((no_atual, 1)))
    n_anterior = func.count(case((no_atual, None), else_=1))
    sub = (
        select(
            Sessao.usuario_id,
            # Os dois lados em float: sem isso o SQLAlchemy poe o divisor
            # como NUMERIC no Postgres e a conta depende de cast implicito.
            (
                cast(pontos_atual - pontos_anterior, Float)
                * 100.0
                / cast(pontos_anterior, Float)
            ).label("valor"),
            n_atual.label("sessoes"),
        )
        .where(
            Sessao.iniciada_em >= inicio,
            Sessao.iniciada_em <= ref,
            Sessao.pontuacao_total.is_not(None),
        )
        .group_by(Sessao.usuario_id)
        .having(
            n_atual >= MINIMO_SESSOES_EVOLUCAO,
            n_anterior >= MINIMO_SESSOES_EVOLUCAO,
            # Percentual sobre zero (ou negativo) nao tem sentido.
            pontos_anterior > 0,
        )
    )
    return sub.subquery(), Periodo(de=meio, ate=ref)


def _item(metrica: Metrica, posicao: int, apelido: str, valor, sessoes) -> ItemRanking:
    # PRIVACIDADE 1: so apelido sai daqui, nunca o usuario inteiro.
    valor = round(float(valor), 1) if metrica == "evolucao" else int(valor)
    return ItemRanking(posicao=posicao, apelido=apelido, valor=valor, sessoes=sessoes)


@router.get("", response_model=RankingSaida)
def ranking(
    metrica: Metrica = Query(...),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(usuario_atual),
    ref: datetime = Depends(agora),
):
    """Os 20 primeiros da metrica e, a parte, a posicao de quem chamou.

    Ordem: maior valor primeiro; empate decidido pelo apelido (unico), para
    a ordem nao mudar entre duas chamadas. Posicoes sao sequenciais.

    `periodo`: em `pontos` e `evolucao`, os ultimos 30 dias (a evolucao os
    compara com os 30 anteriores); em `frequencia`, os 7 dias de calendario
    de Sao Paulo terminados hoje.
    """
    agregado, periodo = _agregado(metrica, ref)
    publico = _aparece_para_os_outros(ref.astimezone(ZONA).date())

    linhas = db.execute(
        select(Usuario.apelido, agregado.c.valor, agregado.c.sessoes)
        .join(Usuario, Usuario.id == agregado.c.usuario_id)
        .where(publico)
        .order_by(agregado.c.valor.desc(), Usuario.apelido.asc())
        .limit(TAMANHO_LISTA)
    ).all()
    itens = [
        _item(metrica, i, apelido, valor, sessoes)
        for i, (apelido, valor, sessoes) in enumerate(linhas, start=1)
    ]

    meu = db.execute(
        select(agregado.c.valor, agregado.c.sessoes).where(
            agregado.c.usuario_id == usuario.id
        )
    ).first()

    voce = None
    if meu is not None:
        # PRIVACIDADE 3: a posicao conta so quem aparece na lista publica e
        # esta a frente, entao vale igual para quem esta nela e para quem
        # foi deixado de fora (menor de idade, sem data de nascimento).
        a_frente = db.scalar(
            select(func.count())
            .select_from(agregado)
            .join(Usuario, Usuario.id == agregado.c.usuario_id)
            .where(
                publico,
                agregado.c.usuario_id != usuario.id,
                or_(
                    agregado.c.valor > meu.valor,
                    and_(
                        agregado.c.valor == meu.valor,
                        Usuario.apelido < usuario.apelido,
                    ),
                ),
            )
        )
        # A mesma regra da lista, avaliada pelo banco para quem chamou, em vez
        # de uma copia em Python que poderia divergir dela com o tempo.
        aparece = db.scalar(
            select(func.count()).select_from(Usuario).where(
                Usuario.id == usuario.id, publico
            )
        )
        item = _item(metrica, a_frente + 1, usuario.apelido, meu.valor, meu.sessoes)
        # oculto = fora da lista POR REGRA (PRIVACIDADE 2), nao por estar
        # abaixo dos 20. Sem isso o app diria a um adulto em 25o que ele "nao
        # aparece", o que e falso: ele esta no ranking e pode subir.
        voce = VoceRanking(**item.model_dump(), oculto=not aparece)

    return RankingSaida(metrica=metrica, periodo=periodo, itens=itens, voce=voce)
