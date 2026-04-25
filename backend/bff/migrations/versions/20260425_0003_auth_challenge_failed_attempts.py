from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260425_0003"
down_revision = "20260425_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {column["name"] for column in inspector.get_columns("auth_challenges")}
    if "failed_attempts" in columns:
        return

    with op.batch_alter_table("auth_challenges") as batch_op:
        batch_op.add_column(
            sa.Column("failed_attempts", sa.Integer(), nullable=False, server_default="0")
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {column["name"] for column in inspector.get_columns("auth_challenges")}
    if "failed_attempts" not in columns:
        return

    with op.batch_alter_table("auth_challenges") as batch_op:
        batch_op.drop_column("failed_attempts")
