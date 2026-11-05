"""Lance: bola unica por sessao e ON DELETE CASCADE

Revision ID: d4f8b2c6e1a7
Revises: c7d2a9e41f30
Create Date: 2026-11-05 22:00:00.000000

- uq_lance_sessao_bola: um numero de bola por sessao. A pontuacao ordena
  por `bola`; repetido, o placar dependeria da ordem de chegada.
- lance.sessao_id com ON DELETE CASCADE: apagar uma sessao por SQL ou
  script leva os lances junto (antes so o painel fazia isso, a mao).

ANTES de rodar em producao, confirmar que nao ha duplicatas, ou a criacao
do indice falha:

    SELECT sessao_id, bola, count(*) FROM lance
    GROUP BY sessao_id, bola HAVING count(*) > 1;

A migration nao resolve duplicatas sozinha de proposito: qual lance fica e
decisao de dado, nao de esquema.
"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'd4f8b2c6e1a7'
down_revision: Union[str, Sequence[str], None] = 'c7d2a9e41f30'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_unique_constraint(
        'uq_lance_sessao_bola', 'lance', ['sessao_id', 'bola']
    )
    op.drop_constraint('lance_sessao_id_fkey', 'lance', type_='foreignkey')
    op.create_foreign_key(
        'lance_sessao_id_fkey', 'lance', 'sessao',
        ['sessao_id'], ['id'], ondelete='CASCADE',
    )


def downgrade() -> None:
    op.drop_constraint('lance_sessao_id_fkey', 'lance', type_='foreignkey')
    op.create_foreign_key(
        'lance_sessao_id_fkey', 'lance', 'sessao', ['sessao_id'], ['id'],
    )
    op.drop_constraint('uq_lance_sessao_bola', 'lance', type_='unique')
