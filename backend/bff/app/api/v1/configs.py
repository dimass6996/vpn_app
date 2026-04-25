from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import DbSession, get_current_user_id
from app.schemas.configs import ConfigItem, ConfigListResponse
from app.services.config_service import config_service


router = APIRouter(tags=["configs"])


@router.get("/configs", response_model=ConfigListResponse)
def get_configs(
    user_id: Annotated[str, Depends(get_current_user_id)],
    db: DbSession,
) -> ConfigListResponse:
    items = config_service.get_configs(db=db, user_id=user_id)
    return ConfigListResponse(items=[ConfigItem(**item) for item in items])
