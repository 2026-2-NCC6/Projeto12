"""Pontuacao autoritativa (US-705)

Revision ID: c7d2a9e41f30
Revises: b3e1f0a2c4d6
Create Date: 2026-11-04 21:30:00.000000

- sessao.versao_pontuacao: qual versao da regra gerou pontuacao_total
  (nula = ainda nao pontuada);
- sessao.dificuldade: graus somados ao limiar de KO naquela sessao;
- lance.angulo de FLOAT para NUMERIC(4,1): a pontuacao converte o angulo
  para decimos de grau de forma exata, entao ele nao pode voltar do banco
  como ponto flutuante.

Nao recalcula nada: as sessoes ja gravadas sao pontuadas pelo comando
`python -m src.scripts.recalcular_pontuacao`. Migration que importa
codigo da aplicacao quebra quando o codigo muda.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c7d2a9e41f30'
down_revision: Union[str, Sequence[str], None] = 'b3e1f0a2c4d6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('sessao', sa.Column('versao_pontuacao', sa.Integer(), nullable=True))
    op.add_column(
        'sessao',
        sa.Column(
            'dificuldade',
            sa.Numeric(precision=3, scale=1),
            nullable=False,
            server_default='0',
        ),
    )
    # Angulos com mais de uma casa (aceitos antes desta US) sao
    # arredondados para uma casa pelo proprio cast.
    op.alter_column(
        'lance',
        'angulo',
        existing_type=sa.Float(),
        type_=sa.Numeric(precision=4, scale=1),
        postgresql_using='angulo::numeric(4,1)',
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column(
        'lance',
        'angulo',
        existing_type=sa.Numeric(precision=4, scale=1),
        type_=sa.Float(),
        postgresql_using='angulo::double precision',
    )
    op.drop_column('sessao', 'dificuldade')
    op.drop_column('sessao', 'versao_pontuacao')
