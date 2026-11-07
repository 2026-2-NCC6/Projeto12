"""calibrado_em no usuario

Marca quando a calibracao foi feita. Nulo = nunca calibrou. O valor da
calibracao nao serve de marca: quem calibra com mediana de 38 graus ou
menos recebe 0, igual a quem nunca calibrou.

Revision ID: e2a9c4b7d031
Revises: d4f8b2c6e1a7
Create Date: 2026-11-06 21:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = 'e2a9c4b7d031'
down_revision: Union[str, Sequence[str], None] = 'd4f8b2c6e1a7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Sem preenchimento retroativo: de quem ja tem calibracao > 0 sabemos
    # que calibrou, mas nao quando; inventar um instante seria pior que nulo.
    op.add_column(
        'usuario',
        sa.Column('calibrado_em', sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('usuario', 'calibrado_em')
