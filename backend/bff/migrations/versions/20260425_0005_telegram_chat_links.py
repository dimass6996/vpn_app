from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260425_0005"
down_revision = "20260425_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "telegram_chat_links" in tables:
        return

    op.create_table(
        "telegram_chat_links",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True, nullable=False),
        sa.Column("telegram_username", sa.String(length=128), nullable=False),
        sa.Column("chat_id", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index(
        op.f("ix_telegram_chat_links_telegram_username"),
        "telegram_chat_links",
        ["telegram_username"],
        unique=True,
    )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    tables = set(inspector.get_table_names())
    if "telegram_chat_links" not in tables:
        return

    op.drop_index(op.f("ix_telegram_chat_links_telegram_username"), table_name="telegram_chat_links")
    op.drop_table("telegram_chat_links")
