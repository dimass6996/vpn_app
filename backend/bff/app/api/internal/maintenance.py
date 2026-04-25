from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import DbSession, require_internal_admin_key
from app.schemas.maintenance import CleanupResponse
from app.services.auth_service import auth_service


router = APIRouter(prefix="/maintenance", tags=["internal-maintenance"])


@router.post("/cleanup-auth", response_model=CleanupResponse)
def cleanup_auth_data(
    db: DbSession,
    _: Annotated[None, Depends(require_internal_admin_key)],
) -> CleanupResponse:
    data = auth_service.cleanup_expired_auth_data(db=db)
    return CleanupResponse(**data)
