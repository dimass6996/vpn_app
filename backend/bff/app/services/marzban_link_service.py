from __future__ import annotations

from dataclasses import dataclass

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.security import utcnow
from app.db.models.user import User
from app.services.audit_service import audit_service
from app.services.marzban_client import MarzbanError, marzban_client


@dataclass
class MarzbanLinkResult:
    username: str | None
    status: str


class MarzbanLinkService:
    def ensure_link(self, db: Session, user: User) -> MarzbanLinkResult:
        if not marzban_client.is_configured():
            self._set_link_state(
                db=db,
                user=user,
                status="pending",
                sync=False,
            )
            return MarzbanLinkResult(username=user.marzban_username, status=user.marzban_link_status)

        target_username = user.marzban_username or self._build_username(user)
        remote_user = marzban_client.get_user(target_username)
        if remote_user is None:
            payload = {
                "username": target_username,
            }
            marzban_client.create_user(payload)

        user.marzban_username = target_username
        self._set_link_state(
            db=db,
            user=user,
            status="linked",
            sync=True,
        )
        audit_service.log(
            db=db,
            user_id=user.external_id,
            action="marzban.link.ensure",
            details=f"status=linked;marzban_username={target_username}",
        )
        return MarzbanLinkResult(username=target_username, status=user.marzban_link_status)

    def link_existing_user(self, db: Session, user: User, marzban_username: str) -> MarzbanLinkResult:
        normalized = marzban_username.strip()
        if not normalized:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Marzban username is required",
            )
        existing = db.scalar(
            select(User).where(
                User.marzban_username == normalized,
                User.external_id != user.external_id,
            )
        )
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Marzban username is already linked to another app user",
            )
        remote_user = marzban_client.get_user(normalized)
        if remote_user is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Marzban user not found",
            )

        user.marzban_username = normalized
        self._set_link_state(db=db, user=user, status="linked", sync=True)
        audit_service.log(
            db=db,
            user_id=user.external_id,
            action="marzban.link.manual",
            details=f"status=linked;marzban_username={normalized}",
        )
        return MarzbanLinkResult(username=normalized, status=user.marzban_link_status)

    def resolve_username(self, db: Session, user: User, *, auto_create: bool) -> str | None:
        try:
            if auto_create:
                result = self.ensure_link(db=db, user=user)
            else:
                result = MarzbanLinkResult(username=user.marzban_username, status=user.marzban_link_status)
        except MarzbanError as exc:
            self._set_link_state(db=db, user=user, status="error", sync=False)
            audit_service.log(
                db=db,
                user_id=user.external_id,
                action="marzban.link.error",
                details=str(exc),
            )
            return None
        return result.username

    def _build_username(self, user: User) -> str:
        return f"app_{user.id}"

    def _set_link_state(
        self,
        db: Session,
        user: User,
        *,
        status: str,
        sync: bool,
    ) -> None:
        user.marzban_link_status = status
        user.marzban_last_sync_at = utcnow() if sync else user.marzban_last_sync_at
        db.add(user)
        db.commit()
        db.refresh(user)


marzban_link_service = MarzbanLinkService()
