from __future__ import annotations

import hashlib

from alembic import op
import sqlalchemy as sa


revision = "20260425_0002"
down_revision = "20260425_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {column["name"] for column in inspector.get_columns("auth_challenges")}
    has_legacy_code = "code" in columns
    has_code_hash = "code_hash" in columns
    has_delivery_hint = "delivery_hint" in columns

    with op.batch_alter_table("auth_challenges") as batch_op:
        if not has_code_hash:
            batch_op.add_column(sa.Column("code_hash", sa.String(length=128), nullable=True))
        if not has_delivery_hint:
            batch_op.add_column(
                sa.Column("delivery_hint", sa.String(length=256), nullable=False, server_default="")
            )

    if has_legacy_code:
        rows = bind.execute(sa.text("SELECT id, code FROM auth_challenges")).fetchall()
        for row in rows:
            code_hash = hashlib.sha256(f"otp:{row.code}".encode("utf-8")).hexdigest()
            bind.execute(
                sa.text("UPDATE auth_challenges SET code_hash = :code_hash WHERE id = :challenge_id"),
                {"code_hash": code_hash, "challenge_id": row.id},
            )

        with op.batch_alter_table("auth_challenges") as batch_op:
            batch_op.alter_column("code_hash", existing_type=sa.String(length=128), nullable=False)
            batch_op.drop_column("code")


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = {column["name"] for column in inspector.get_columns("auth_challenges")}
    has_code_hash = "code_hash" in columns
    has_delivery_hint = "delivery_hint" in columns
    has_code = "code" in columns

    with op.batch_alter_table("auth_challenges") as batch_op:
        if not has_code:
            batch_op.add_column(sa.Column("code", sa.String(length=32), nullable=True))

    if has_code_hash:
        rows = bind.execute(sa.text("SELECT id, code_hash FROM auth_challenges")).fetchall()
        for row in rows:
            bind.execute(
                sa.text("UPDATE auth_challenges SET code = :code WHERE id = :challenge_id"),
                {"code": "migrated-unrecoverable", "challenge_id": row.id},
            )

        with op.batch_alter_table("auth_challenges") as batch_op:
            batch_op.alter_column("code", existing_type=sa.String(length=32), nullable=False)
            if has_delivery_hint:
                batch_op.drop_column("delivery_hint")
            batch_op.drop_column("code_hash")
