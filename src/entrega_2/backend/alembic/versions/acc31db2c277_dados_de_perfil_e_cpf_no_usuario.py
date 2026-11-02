"""Dados de perfil e CPF no usuario

Revision ID: acc31db2c277
Revises: 611581d6f78f
Create Date: 2026-10-28 23:07:12.918879

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'acc31db2c277'
down_revision: Union[str, Sequence[str], None] = '611581d6f78f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    perfil_enum = sa.Enum(
        'casual', 'iniciante', 'infantil', name='perfil_jogador'
    )
    perfil_enum.create(op.get_bind())

    op.add_column('usuario', sa.Column('nome', sa.String(length=120), nullable=False))
    op.add_column('usuario', sa.Column('apelido', sa.String(length=40), nullable=False))
    op.add_column('usuario', sa.Column('cpf', sa.String(length=11), nullable=False))
    op.add_column('usuario', sa.Column('data_nascimento', sa.Date(), nullable=False))
    op.add_column('usuario', sa.Column('perfil', perfil_enum, nullable=False))
    op.create_index(op.f('ix_usuario_apelido'), 'usuario', ['apelido'], unique=True)
    op.create_unique_constraint('uq_usuario_cpf', 'usuario', ['cpf'])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint('uq_usuario_cpf', 'usuario', type_='unique')
    op.drop_index(op.f('ix_usuario_apelido'), table_name='usuario')
    op.drop_column('usuario', 'perfil')
    op.drop_column('usuario', 'data_nascimento')
    op.drop_column('usuario', 'cpf')
    op.drop_column('usuario', 'apelido')
    op.drop_column('usuario', 'nome')
    sa.Enum(name='perfil_jogador').drop(op.get_bind())