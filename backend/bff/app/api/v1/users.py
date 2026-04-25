from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import get_current_user
from app.db.models.user import User
from app.schemas.user import MeResponse


router = APIRouter(tags=["users"])


@router.get("/me", response_model=MeResponse)
def get_me(user: Annotated[User, Depends(get_current_user)]) -> MeResponse:
    return MeResponse(
        user_id=user.external_id,
        username=user.username,
        auth_provider=user.auth_provider,
    )
