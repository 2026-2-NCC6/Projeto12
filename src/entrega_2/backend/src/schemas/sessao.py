import uuid
from datetime import timezone
from decimal import Decimal
from typing import Literal, Optional

from pydantic import AwareDatetime, BaseModel, Field, field_validator, model_validator

from src.models.sessao import ClasseImpacto, TipoLance

# Limite da coluna ts_ms (INTEGER de 32 bits): ~24 dias de sessao.
TS_MS_MAXIMO = 2_147_483_647

# Maior total possivel: 500 lances x (100 x 200% + 75 de KO) = 137.500.
PONTUACAO_MAXIMA = 1_000_000


class LanceEntrada(BaseModel):
    """Um lance como o app recebeu do firmware, mais o UUID do app."""

    uuid_lance: uuid.UUID
    id_lance_firmware: Optional[str] = Field(default=None, max_length=40)
    bola: int = Field(ge=1, le=500)
    resultado: TipoLance
    classe: ClasseImpacto
    # classe e knockout sao interpretacoes do firmware: aceitos e
    # guardados, mas a pontuacao nao os usa (o KO e recalculado).
    knockout: bool = False
    # Decimal com no maximo 1 casa, lido direto do texto do JSON: a
    # conversao para decimos de grau e exata por construcao (US-705).
    angulo: Decimal = Field(ge=0, le=180, decimal_places=1)
    ts_ms: int = Field(ge=0, le=TS_MS_MAXIMO)

    @model_validator(mode="after")
    def coerente(self):
        """Erro e "nenhum impacto": sem classe, sem KO e sem angulo.

        E o que o firmware ja emite no timeout (registrarErroTimeout).
        O inverso tambem vale: acerto sempre teve impacto.
        """
        if self.resultado == TipoLance.erro:
            if (
                self.classe != ClasseImpacto.sem_impacto
                or self.knockout
                or self.angulo != 0
            ):
                raise ValueError(
                    "lance com resultado 'erro' exige classe 'sem_impacto', "
                    "knockout false e angulo 0"
                )
        elif self.classe == ClasseImpacto.sem_impacto:
            raise ValueError("lance com resultado 'acerto' nao pode ser 'sem_impacto'")
        return self


class SessaoEntrada(BaseModel):
    """Uma sessao do lote.

    Agregados (acertos, kos, precisao...) nao fazem parte do contrato:
    se o cliente mandar, sao ignorados e o servidor recalcula.
    """

    uuid_sessao: uuid.UUID
    treino_versao_id: int = Field(ge=1)
    iniciada_em: AwareDatetime
    encerrada_em: Optional[AwareDatetime] = None
    lances: list[LanceEntrada] = Field(default_factory=list, max_length=500)

    # Graus somados ao limiar de KO nesta sessao (TREINO:qtd:intervalo:calib).
    # Mesma faixa do CalibracaoEntrada. Imutavel apos a primeira gravacao.
    dificuldade: Decimal = Field(default=Decimal("0"), ge=0, le=45, decimal_places=1)

    # Placar que o app calculou. So e comparado com o do servidor para
    # detectar divergencia; nunca e gravado como pontuacao oficial.
    pontuacao_cliente: Optional[int] = Field(default=None, ge=0, le=PONTUACAO_MAXIMA)

    @field_validator("iniciada_em", "encerrada_em")
    @classmethod
    def em_utc(cls, valor):
        """Converte para UTC preservando o instante.

        O Postgres ja guarda timestamptz em UTC, entao la nada muda. Mas
        um banco sem fuso (o SQLite dos testes) guardaria so o numero do
        relogio e perderia o instante: 08:15-03:00 e 13:15+02:00 virariam
        horarios diferentes. Normalizar aqui fecha isso em qualquer banco.
        """
        return valor.astimezone(timezone.utc) if valor is not None else None

    @model_validator(mode="after")
    def datas_em_ordem(self):
        if self.encerrada_em is not None and self.encerrada_em < self.iniciada_em:
            raise ValueError("encerrada_em nao pode ser anterior a iniciada_em")
        return self


class LoteEntrada(BaseModel):
    sessoes: list[SessaoEntrada] = Field(min_length=1, max_length=50)


class ResumoSessaoSaida(BaseModel):
    """Resultado do processamento de uma sessao do lote.

    `motivo` e generico de proposito: "versao_invalida" cobre tanto a
    versao que nao existe quanto a de outro dono, para nao revelar qual.
    """

    uuid_sessao: uuid.UUID
    situacao: Literal["inserida", "ja_existia", "rejeitada"]
    motivo: Optional[Literal["versao_invalida"]] = None
    lances_recebidos: int
    lances_inseridos: int
    lances_duplicados: int
    # Pontuacao oficial, calculada pelo servidor; o app deve exibir esta.
    # Nula quando a sessao foi rejeitada.
    pontuacao_total: Optional[int] = None


class LoteSaida(BaseModel):
    sessoes: list[ResumoSessaoSaida]
