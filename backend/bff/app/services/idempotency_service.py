import json

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models.idempotency_key import IdempotencyKey


class IdempotencyService:
    def get_response(self, db: Session, key: str, scope: str) -> dict[str, str | bool] | None:
        record = db.scalar(
            select(IdempotencyKey).where(
                IdempotencyKey.key == key,
                IdempotencyKey.scope == scope,
            )
        )
        if record is None:
            return None
        return json.loads(record.response_payload)

    def store_response(
        self,
        db: Session,
        key: str,
        scope: str,
        response_payload: dict[str, str | bool],
    ) -> dict[str, str | bool]:
        record = IdempotencyKey(
            key=key,
            scope=scope,
            response_payload=json.dumps(response_payload),
        )
        db.add(record)
        db.commit()
        return response_payload


idempotency_service = IdempotencyService()
