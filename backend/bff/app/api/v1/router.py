from fastapi import APIRouter

from app.api.v1 import auth, configs, subscription, support, users


api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(subscription.router)
api_router.include_router(configs.router)
api_router.include_router(support.router)
