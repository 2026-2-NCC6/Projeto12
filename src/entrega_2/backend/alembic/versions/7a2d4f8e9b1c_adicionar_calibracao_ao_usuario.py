"""Adicionar calibracao ao usuario

Revision ID: 7a2d4f8e9b1c
Revises: e6bf29c378ff
Create Date: 2026-11-02 21:26:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7a2d4f8e9b1c'
down_revision: Union[str, Sequence[str], None] = 'e6bf29c378ff'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column(
        'usuario',
        sa.Column('calibracao', sa.Float(), nullable=False, server_default='0.0')
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('usuario', 'calibracao')

