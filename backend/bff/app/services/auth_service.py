from datetime import timedelta
import secrets

from fastapi import HTTPException, status
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    create_access_token,
    generate_refresh_token,
    hash_otp_code,
    hash_token,
    utcnow,
)
from app.db.models.auth_challenge import AuthChallenge
from app.db.models.auth_session import AuthSession
from app.db.models.user import User
from app.services.audit_service import audit_service
from app.services.auth_delivery_service import auth_delivery_service
from app.services.marzban_link_service import marzban_link_service


class AuthService:
    def start_auth(self, db: Session, login: str, device_id: str) -> dict[str, str]:
        login = login.strip()
        now = utcnow()
        cooldown_cutoff = now - timedelta(seconds=settings.auth_resend_cooldown_seconds)
        recent_challenge = db.scalar(
            select(AuthChallenge)
            .where(
                AuthChallenge.login == login,
                AuthChallenge.is_used.is_(False),
                AuthChallenge.expires_at >= now,
                AuthChallenge.created_at >= cooldown_cutoff,
            )
            .order_by(AuthChallenge.created_at.desc())
        )
        if recent_challenge is not None:
            retry_at = recent_challenge.created_at + timedelta(
                seconds=settings.auth_resend_cooldown_seconds
            )
            retry_in_seconds = max(1, int((retry_at - now).total_seconds()))
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=f"OTP recently sent. Retry in {retry_in_seconds}s",
            )

        db.execute(
            update(AuthChallenge)
            .where(
                AuthChallenge.login == login,
                AuthChallenge.is_used.is_(False),
                AuthChallenge.expires_at >= now,
            )
            .values(is_used=True)
        )

        challenge_id = secrets.token_urlsafe(18)
        expires_at = now + timedelta(minutes=settings.auth_challenge_ttl_minutes)
        issued_code = auth_delivery_service.issue_code(login, device_id, challenge_id, db=db)
        challenge = AuthChallenge(
            id=challenge_id,
            login=login,
            code_hash=hash_otp_code(issued_code.code),
            method=issued_code.method,
            delivery_hint=issued_code.delivery_hint,
            expires_at=expires_at,
            failed_attempts=0,
        )
        db.add(challenge)
        db.commit()

        audit_service.log(
            db=db,
            user_id=login,
            action="auth.challenge.created",
            details=f"device_id={device_id};method={issued_code.method}",
        )
        return {
            "challenge_id": challenge_id,
            "method": issued_code.method,
            "delivery_hint": issued_code.delivery_hint,
            "magic_link": issued_code.magic_link,
        }

    def verify_auth(
        self,
        db: Session,
        challenge_id: str,
        code: str,
        device_id: str,
    ) -> dict[str, str | int]:
        challenge = db.scalar(select(AuthChallenge).where(AuthChallenge.id == challenge_id))
        if challenge is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Challenge not found")
        if challenge.is_used:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Challenge already used")
        if challenge.expires_at < utcnow():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Challenge expired")
        if challenge.failed_attempts >= settings.auth_verify_max_attempts:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Too many attempts for this code. Request a new OTP",
            )
        if challenge.code_hash != hash_otp_code(code):
            challenge.failed_attempts += 1
            if challenge.failed_attempts >= settings.auth_verify_max_attempts:
                challenge.is_used = True
            db.commit()
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid verification code")

        user = db.scalar(select(User).where(User.external_id == challenge.login))
        if user is None:
            user = User(
                external_id=challenge.login,
                username=challenge.login,
                auth_provider=challenge.method,
            )
            db.add(user)
            db.flush()

        refresh_token = generate_refresh_token()
        session_id = secrets.token_urlsafe(18)
        session = AuthSession(
            id=session_id,
            user_external_id=user.external_id,
            refresh_token_hash=hash_token(refresh_token),
            device_id=device_id,
            expires_at=utcnow() + timedelta(days=settings.refresh_token_expire_days),
        )
        challenge.is_used = True
        db.add(session)
        db.commit()

        try:
            marzban_link_service.resolve_username(db=db, user=user, auto_create=True)
        except Exception:
            # Auth should remain available even if Marzban is down.
            pass

        access_token, _ = create_access_token(subject=user.external_id, session_id=session.id)
        audit_service.log(
            db=db,
            user_id=user.external_id,
            action="auth.login.success",
            details=f"device_id={device_id}",
        )
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_in": settings.access_token_expire_minutes * 60,
        }

    def refresh_access(self, db: Session, refresh_token: str) -> dict[str, str | int]:
        token_hash = hash_token(refresh_token)
        session = db.scalar(select(AuthSession).where(AuthSession.refresh_token_hash == token_hash))
        if session is None or session.is_revoked:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
        if session.expires_at < utcnow():
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token expired")

        access_token, _ = create_access_token(subject=session.user_external_id, session_id=session.id)
        audit_service.log(
            db=db,
            user_id=session.user_external_id,
            action="auth.token.refreshed",
            details=f"session_id={session.id}",
        )
        return {
            "access_token": access_token,
            "expires_in": settings.access_token_expire_minutes * 60,
        }

    def logout(
        self,
        db: Session,
        *,
        user_id: str,
        session_id: str,
        refresh_token: str | None = None,
    ) -> dict[str, int | bool]:
        revoked_sessions = 0

        session = db.scalar(select(AuthSession).where(AuthSession.id == session_id))
        if session is not None and not session.is_revoked:
            session.is_revoked = True
            revoked_sessions += 1

        if refresh_token:
            token_hash = hash_token(refresh_token)
            refresh_session = db.scalar(
                select(AuthSession).where(AuthSession.refresh_token_hash == token_hash)
            )
            if refresh_session is not None and not refresh_session.is_revoked:
                if refresh_session.id != session_id:
                    revoked_sessions += 1
                refresh_session.is_revoked = True

        db.commit()
        audit_service.log(
            db=db,
            user_id=user_id,
            action="auth.logout",
            details=f"revoked_sessions={revoked_sessions}",
        )
        return {"success": True, "revoked_sessions": revoked_sessions}

    def logout_all(self, db: Session, *, user_id: str) -> dict[str, int | bool]:
        result = db.execute(
            update(AuthSession)
            .where(
                AuthSession.user_external_id == user_id,
                AuthSession.is_revoked.is_(False),
            )
            .values(is_revoked=True)
        )
        db.commit()
        revoked_sessions = int(result.rowcount or 0)
        audit_service.log(
            db=db,
            user_id=user_id,
            action="auth.logout_all",
            details=f"revoked_sessions={revoked_sessions}",
        )
        return {"success": True, "revoked_sessions": revoked_sessions}

    def cleanup_expired_auth_data(self, db: Session) -> dict[str, int]:
        now = utcnow()
        deleted_challenges = int(
            db.execute(delete(AuthChallenge).where(AuthChallenge.expires_at < now)).rowcount or 0
        )
        deleted_sessions = int(
            db.execute(delete(AuthSession).where(AuthSession.expires_at < now)).rowcount or 0
        )
        db.commit()
        return {
            "deleted_challenges": deleted_challenges,
            "deleted_sessions": deleted_sessions,
        }


auth_service = AuthService()
