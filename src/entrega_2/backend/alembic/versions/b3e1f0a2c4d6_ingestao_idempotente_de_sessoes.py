"""Ingestao idempotente de sessoes (US-704)

Revision ID: b3e1f0a2c4d6
Revises: 7a2d4f8e9b1c
Create Date: 2026-11-04 18:00:00.000000

Separa identidade interna (sessao.id, do servidor) de chave de
idempotencia (sessao.uuid_sessao, do app), com unicidade por usuario.
O lance passa a ser unico por (sessao_id, uuid_lance), ganha a coluna
informativa id_lance_firmware e tres colunas sao renomeadas.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b3e1f0a2c4d6'
down_revision: Union[str, Sequence[str], None] = '7a2d4f8e9b1c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # --- sessao ---------------------------------------------------------
    # Sessoes ja gravadas usavam o UUID do app como id: ele vira a chave
    # de idempotencia delas, e o id continua o mesmo (as FKs nao mudam).
    op.add_column('sessao', sa.Column('uuid_sessao', sa.UUID(), nullable=True))
    op.execute('UPDATE sessao SET uuid_sessao = id')
    op.alter_column('sessao', 'uuid_sessao', nullable=False)
    op.create_unique_constraint(
        'uq_sessao_usuario_uuid', 'sessao', ['usuario_id', 'uuid_sessao']
    )

    # Pontuacao fica nula ate a US-705.
    op.alter_column(
        'sessao', 'pontuacao_total', existing_type=sa.Integer(), nullable=True
    )
    op.add_column('sessao', sa.Column('media_angulo', sa.Float(), nullable=True))
    op.add_column('sessao', sa.Column('max_angulo', sa.Float(), nullable=True))
    op.add_column('sessao', sa.Column('precisao', sa.Float(), nullable=True))

    # --- lance ----------------------------------------------------------
    op.alter_column('lance', 'numero', new_column_name='bola')
    op.alter_column('lance', 'tipo', new_column_name='resultado')
    op.alter_column('lance', 'intensidade', new_column_name='angulo')
    op.add_column(
        'lance', sa.Column('id_lance_firmware', sa.String(length=40), nullable=True)
    )

    # Unicidade global de uuid_lance vazava a existencia de lances de
    # outros usuarios. Passa a valer so dentro da sessao.
    op.drop_constraint('lance_uuid_lance_key', 'lance', type_='unique')
    op.create_unique_constraint(
        'uq_lance_sessao_uuid', 'lance', ['sessao_id', 'uuid_lance']
    )

    # ADD VALUE fora da transacao: o Postgres nao deixa usar o valor novo
    # na mesma transacao em que ele foi criado.
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE classe_impacto ADD VALUE IF NOT EXISTS 'sem_impacto'")


def downgrade() -> None:
    """Downgrade schema."""
    # Postgres nao remove valor de enum: recria o tipo sem 'sem_impacto'.
    op.execute("UPDATE lance SET classe = NULL WHERE classe = 'sem_impacto'")
    op.execute('ALTER TYPE classe_impacto RENAME TO classe_impacto_old')
    op.execute("CREATE TYPE classe_impacto AS ENUM ('fraco', 'medio', 'forte')")
    op.execute(
        'ALTER TABLE lance ALTER COLUMN classe TYPE classe_impacto '
        'USING classe::text::classe_impacto'
    )
    op.execute('DROP TYPE classe_impacto_old')

    # Volta a unicidade global; falha se houver o mesmo uuid_lance em
    # duas sessoes, o que e o comportamento correto para um downgrade.
    op.drop_constraint('uq_lance_sessao_uuid', 'lance', type_='unique')
    op.create_unique_constraint('lance_uuid_lance_key', 'lance', ['uuid_lance'])

    op.drop_column('lance', 'id_lance_firmware')
    op.alter_column('lance', 'angulo', new_column_name='intensidade')
    op.alter_column('lance', 'resultado', new_column_name='tipo')
    op.alter_column('lance', 'bola', new_column_name='numero')

    op.drop_column('sessao', 'precisao')
    op.drop_column('sessao', 'max_angulo')
    op.drop_column('sessao', 'media_angulo')
    op.execute('UPDATE sessao SET pontuacao_total = 0 WHERE pontuacao_total IS NULL')
    op.alter_column(
        'sessao', 'pontuacao_total', existing_type=sa.Integer(), nullable=False
    )
    op.drop_constraint('uq_sessao_usuario_uuid', 'sessao', type_='unique')
    op.drop_column('sessao', 'uuid_sessao')
