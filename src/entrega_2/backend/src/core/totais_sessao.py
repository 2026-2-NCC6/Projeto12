from sqlalchemy import select
from sqlalchemy.orm import Session

from src.core import pontuacao
from src.models.sessao import Lance, Sessao, TipoLance


def recalcular_totais(db: Session, sessao: Sessao) -> list[Lance]:
    """Recalcula todos os agregados da sessao a partir dos lances gravados.

    Sempre a sessao inteira, nunca incremental: lances que chegam depois
    mudam a sequencia (e o multiplicador) dos que vieram antes deles.

    So medidas brutas entram na conta: `resultado`, `angulo` e a
    `dificuldade` da sessao. `classe` e `knockout` recebidos sao ignorados;
    o KO vem da regra de pontuacao. Devolve os lances, na ordem pontuada.
    """
    lances = list(
        db.scalars(
            select(Lance)
            .where(Lance.sessao_id == sessao.id)
            .order_by(Lance.bola, Lance.ts_ms, Lance.id)
        ).all()
    )

    resultado = pontuacao.calcular(
        [
            pontuacao.LanceBruto(
                bola=l.bola,
                resultado=l.resultado.value,
                angulo_decimos=pontuacao.decimos(l.angulo or 0),
            )
            for l in lances
        ],
        dificuldade_decimos=pontuacao.decimos(sessao.dificuldade or 0),
    )

    for lance, pontos in zip(lances, resultado.pontos_por_lance):
        lance.pontos = pontos

    acertos = [l for l in lances if l.resultado == TipoLance.acerto]
    angulos = [l.angulo for l in acertos if l.angulo is not None]

    sessao.acertos = len(acertos)
    sessao.erros = len(lances) - len(acertos)
    sessao.kos = resultado.kos
    sessao.melhor_sequencia = resultado.melhor_sequencia
    sessao.pontuacao_total = resultado.pontuacao_total
    sessao.versao_pontuacao = pontuacao.VERSAO_REGRA

    # Estatisticas de exibicao (nao entram na pontuacao).
    sessao.media_angulo = (
        float(round(sum(angulos) / len(angulos), 1)) if angulos else None
    )
    sessao.max_angulo = float(max(angulos)) if angulos else None
    sessao.precisao = (
        round(len(acertos) * 100 / len(lances), 1) if lances else None
    )

    return lances
