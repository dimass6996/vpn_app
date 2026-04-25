from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import TokenError, decode_access_token, utcnow
from app.db.models.auth_session import AuthSession
from app.db.models.user import User
from app.db.session import get_db_session
from app.services.rate_limit_service import default_auth_limits, rate_limit_service


DbSession = Annotated[Session, Depends(get_db_session)]


@dataclass
class AuthContext:
    user: User
    session: AuthSession


def get_auth_context(
    db: DbSession,
    authorization: Annotated[str | None, Header()] = None,
) -> AuthContext:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header",
        )
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Authorization header",
        )

    try:
        payload = decode_access_token(token)
    except TokenError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc

    session = db.scalar(select(AuthSession).where(AuthSession.id == payload["sid"]))
    if session is None or session.is_revoked or session.expires_at < utcnow():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session is not active")

    user = db.scalar(select(User).where(User.external_id == payload["sub"]))
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return AuthContext(user=user, session=session)


def get_current_user(auth_context: Annotated[AuthContext, Depends(get_auth_context)]) -> User:
    return auth_context.user


def get_current_session(auth_context: Annotated[AuthContext, Depends(get_auth_context)]) -> AuthSession:
    return auth_context.session


def get_current_user_id(user: Annotated[User, Depends(get_current_user)]) -> str:
    return user.external_id


def require_internal_admin_key(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
) -> None:
    if x_api_key != settings.internal_admin_api_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid internal API key",
        )


def apply_auth_rate_limit(request: Request) -> None:
    client_host = request.client.host if request.client else "unknown"
    attempts, window = default_auth_limits()
    decision = rate_limit_service.check(
        key=f"auth:{client_host}",
        max_attempts=attempts,
        window_seconds=window,
    )
    if not decision.allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Auth rate limit exceeded. Retry after {decision.retry_after_seconds}s",
        )
