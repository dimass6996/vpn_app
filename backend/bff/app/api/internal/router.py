from fastapi import APIRouter

from app.api.internal import admin, maintenance


internal_router = APIRouter()
internal_router.include_router(admin.router)
internal_router.include_router(maintenance.router)
