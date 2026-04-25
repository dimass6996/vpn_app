from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import DbSession, get_current_user_id
from app.schemas.subscription import SubscriptionResponse
from app.services.subscription_service import subscription_service


router = APIRouter(tags=["subscription"])


@router.get("/subscription", response_model=SubscriptionResponse)
def get_subscription(
    user_id: Annotated[str, Depends(get_current_user_id)],
    db: DbSession,
) -> SubscriptionResponse:
    data = subscription_service.get_subscription(db=db, user_id=user_id)
    return SubscriptionResponse(**data)
