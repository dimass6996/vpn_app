from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260426_0006"
down_revision = "20260425_0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("marzban_username", sa.String(length=128), nullable=True))
    op.add_column(
        "users",
        sa.Column(
            "marzban_link_status",
            sa.String(length=32),
            nullable=False,
            server_default="pending",
        ),
    )
    op.add_column("users", sa.Column("marzban_last_sync_at", sa.DateTime(timezone=True), nullable=True))
    op.create_index(op.f("ix_users_marzban_username"), "users", ["marzban_username"], unique=True)
    op.execute("UPDATE users SET marzban_link_status = 'pending' WHERE marzban_link_status IS NULL")
    op.alter_column("users", "marzban_link_status", server_default=None)


def downgrade() -> None:
    op.drop_index(op.f("ix_users_marzban_username"), table_name="users")
    op.drop_column("users", "marzban_last_sync_at")
    op.drop_column("users", "marzban_link_status")
    op.drop_column("users", "marzban_username")
