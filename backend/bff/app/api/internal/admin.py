from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, status

from app.api.deps import DbSession, require_internal_admin_key
from app.schemas.admin import AdminActionResponse, ExtendRequest, ProvisionRequest
from app.services.admin_service import admin_service
from app.services.idempotency_service import idempotency_service


router = APIRouter(prefix="/admin", tags=["internal-admin"])


@router.post("/provision", response_model=AdminActionResponse)
def provision(
    payload: ProvisionRequest,
    db: DbSession,
    _: Annotated[None, Depends(require_internal_admin_key)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> AdminActionResponse:
    if not idempotency_key:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing Idempotency-Key")
    cached = idempotency_service.get_response(db=db, key=idempotency_key, scope="admin.provision")
    if cached is not None:
        return AdminActionResponse(**cached)

    data = admin_service.provision_user(
        db=db,
        username=payload.username,
        plan_code=payload.plan_code,
    )
    stored = idempotency_service.store_response(
        db=db,
        key=idempotency_key,
        scope="admin.provision",
        response_payload=data,
    )
    return AdminActionResponse(**stored)


@router.post("/extend", response_model=AdminActionResponse)
def extend(
    payload: ExtendRequest,
    db: DbSession,
    _: Annotated[None, Depends(require_internal_admin_key)],
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> AdminActionResponse:
    if not idempotency_key:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing Idempotency-Key")
    cached = idempotency_service.get_response(db=db, key=idempotency_key, scope="admin.extend")
    if cached is not None:
        return AdminActionResponse(**cached)

    data = admin_service.extend_subscription(
        db=db,
        username=payload.username,
        extra_days=payload.extra_days,
    )
    stored = idempotency_service.store_response(
        db=db,
        key=idempotency_key,
        scope="admin.extend",
        response_payload=data,
    )
    return AdminActionResponse(**stored)
