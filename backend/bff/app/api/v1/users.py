from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import get_current_user
from app.db.models.user import User
from app.api.deps import DbSession
from app.schemas.user import MarzbanLinkRequest, MarzbanLinkResponse, MeResponse
from app.services.marzban_link_service import marzban_link_service


router = APIRouter(tags=["users"])


@router.get("/me", response_model=MeResponse)
def get_me(user: Annotated[User, Depends(get_current_user)]) -> MeResponse:
    return MeResponse(
        user_id=user.external_id,
        username=user.username,
        auth_provider=user.auth_provider,
        marzban_username=user.marzban_username,
        marzban_link_status=user.marzban_link_status,
    )


@router.post("/me/marzban/link", response_model=MarzbanLinkResponse)
def link_marzban_user(
    payload: MarzbanLinkRequest,
    db: DbSession,
    user: Annotated[User, Depends(get_current_user)],
) -> MarzbanLinkResponse:
    result = marzban_link_service.link_existing_user(
        db=db,
        user=user,
        marzban_username=payload.marzban_username,
    )
    return MarzbanLinkResponse(
        marzban_username=result.username,
        marzban_link_status=result.status,
    )
