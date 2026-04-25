from fastapi import FastAPI

from app.api.v1.router import api_router
from app.api.internal.router import internal_router
from app.core.config import settings
from app.core.http import install_http_primitives


app = FastAPI(
    title="Arbuz VPN BFF",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

install_http_primitives(app)

app.include_router(api_router, prefix="/api/v1")
app.include_router(internal_router, prefix="/internal")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "env": settings.app_env}
