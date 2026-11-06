from datetime import datetime
from typing import Literal

from pydantic import BaseModel

Metrica = Literal["pontos", "frequencia", "evolucao"]


class Periodo(BaseModel):
    de: datetime
    ate: datetime


class ItemRanking(BaseModel):
    """Uma linha do ranking.

    PRIVACIDADE: estes quatro campos sao tudo o que um usuario ve de outro.
    Nao acrescente id, nome nem e-mail aqui: o apelido ja e unico e basta
    para o ranking. O teste test_nada_alem_do_apelido varre a resposta
    inteira atras de qualquer campo a mais.
    """

    posicao: int
    apelido: str
    # pontos e frequencia: inteiro; evolucao: percentual com 1 casa.
    valor: int | float
    sessoes: int


class VoceRanking(ItemRanking):
    """A linha de quem chamou.

    `oculto`: verdadeiro quando a pessoa foi deixada fora da lista publica
    pelas regras de privacidade (menor de idade, sem data de nascimento);
    falso quando so esta abaixo do corte dos 20. A pessoa fica sabendo de si
    mesma, nada sobre terceiros. Por isso o campo existe SO aqui, e nao em
    ItemRanking: nas linhas dos outros seria um dado sobre eles.
    """

    oculto: bool


class RankingSaida(BaseModel):
    metrica: Metrica
    periodo: Periodo
    itens: list[ItemRanking]
    # Posicao de quem chamou, mesmo fora dos 20 primeiros ou fora da lista
    # publica. Nula se nao treinou no periodo (ou, na evolucao, se nao
    # atingiu o minimo de sessoes).
    voce: VoceRanking | None
