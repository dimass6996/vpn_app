from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import DbSession, get_current_user_id
from app.schemas.support import SupportRequest, SupportResponse
from app.services.support_service import support_service


router = APIRouter(prefix="/support", tags=["support"])


@router.post("/request", response_model=SupportResponse)
def create_support_request(
    payload: SupportRequest,
    user_id: Annotated[str, Depends(get_current_user_id)],
    db: DbSession,
) -> SupportResponse:
    data = support_service.create_ticket(
        db=db,
        user_id=user_id,
        subject=payload.subject,
        message=payload.message,
    )
    return SupportResponse(**data)
