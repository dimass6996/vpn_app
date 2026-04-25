from __future__ import annotations

import logging
from time import perf_counter
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware


REQUEST_ID_HEADER = "X-Request-ID"
REQUEST_ID_STATE_KEY = "request_id"
logger = logging.getLogger("arbuz.http")


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get(REQUEST_ID_HEADER, str(uuid4()))
        setattr(request.state, REQUEST_ID_STATE_KEY, request_id)
        started_at = perf_counter()
        response = await call_next(request)
        response.headers[REQUEST_ID_HEADER] = request_id
        duration_ms = round((perf_counter() - started_at) * 1000, 2)
        logger.info(
            "%s %s -> %s (%sms) request_id=%s",
            request.method,
            request.url.path,
            response.status_code,
            duration_ms,
            request_id,
        )
        return response


def install_http_primitives(app: FastAPI) -> None:
    app.add_middleware(RequestIdMiddleware)

    @app.exception_handler(HTTPException)
    async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "code": "http_error",
                "message": str(exc.detail),
                "request_id": _request_id(request),
                "details": None,
            },
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        request: Request,
        exc: RequestValidationError,
    ) -> JSONResponse:
        details = [
            {"field": ".".join(str(part) for part in error["loc"]), "message": error["msg"]}
            for error in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content={
                "code": "validation_error",
                "message": "Request validation failed",
                "request_id": _request_id(request),
                "details": details,
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        return JSONResponse(
            status_code=500,
            content={
                "code": "internal_error",
                "message": "Unexpected server error",
                "request_id": _request_id(request),
                "details": [{"field": "exception", "message": exc.__class__.__name__}],
            },
        )


def _request_id(request: Request) -> str:
    return getattr(request.state, REQUEST_ID_STATE_KEY, "missing-request-id")
