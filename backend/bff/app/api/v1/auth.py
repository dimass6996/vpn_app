from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import (
    DbSession,
    apply_auth_rate_limit,
    get_current_session,
    get_current_user_id,
)
from app.db.models.auth_session import AuthSession
from app.schemas.auth import (
    AccessTokenResponse,
    AuthStartRequest,
    AuthStartResponse,
    AuthVerifyRequest,
    LogoutRequest,
    LogoutResponse,
    RefreshRequest,
    TokenPairResponse,
)
from app.services.auth_service import auth_service


router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/start", response_model=AuthStartResponse)
def start_auth(
    payload: AuthStartRequest,
    db: DbSession,
    _: Annotated[None, Depends(apply_auth_rate_limit)],
) -> AuthStartResponse:
    data = auth_service.start_auth(db=db, login=payload.login, device_id=payload.device_id)
    return AuthStartResponse(**data)


@router.post("/verify", response_model=TokenPairResponse)
def verify_auth(
    payload: AuthVerifyRequest,
    db: DbSession,
    _: Annotated[None, Depends(apply_auth_rate_limit)],
) -> TokenPairResponse:
    data = auth_service.verify_auth(
        db=db,
        challenge_id=payload.challenge_id,
        code=payload.code,
        device_id=payload.device_id,
    )
    return TokenPairResponse(**data)


@router.post("/refresh", response_model=AccessTokenResponse)
def refresh_auth(
    payload: RefreshRequest,
    db: DbSession,
    _: Annotated[None, Depends(apply_auth_rate_limit)],
) -> AccessTokenResponse:
    data = auth_service.refresh_access(db=db, refresh_token=payload.refresh_token)
    return AccessTokenResponse(**data)


@router.post("/logout", response_model=LogoutResponse)
def logout(
    payload: LogoutRequest,
    db: DbSession,
    user_id: Annotated[str, Depends(get_current_user_id)],
    session: Annotated[AuthSession, Depends(get_current_session)],
) -> LogoutResponse:
    data = auth_service.logout(
        db=db,
        user_id=user_id,
        session_id=session.id,
        refresh_token=payload.refresh_token,
    )
    return LogoutResponse(**data)


@router.post("/logout-all", response_model=LogoutResponse)
def logout_all(
    db: DbSession,
    user_id: Annotated[str, Depends(get_current_user_id)],
) -> LogoutResponse:
    data = auth_service.logout_all(db=db, user_id=user_id)
    return LogoutResponse(**data)
