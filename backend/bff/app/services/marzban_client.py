from __future__ import annotations

from dataclasses import dataclass
from threading import Lock
from typing import Any

import httpx

from app.core.config import settings
from app.core.security import unix_timestamp_now, utcnow


class MarzbanError(RuntimeError):
    pass


class MarzbanUnavailableError(MarzbanError):
    pass


class MarzbanUnauthorizedError(MarzbanError):
    pass


@dataclass
class CachedToken:
    value: str
    expires_at_ts: int


class MarzbanClient:
    def __init__(self) -> None:
        self.base_url = settings.marzban_base_url.rstrip("/")
        self._sudo_username = settings.marzban_sudo_username
        self._sudo_password = settings.marzban_sudo_password
        self._timeout = settings.marzban_request_timeout_seconds
        self._token_cache_seconds = settings.marzban_admin_token_cache_seconds
        self._cached_token: CachedToken | None = None
        self._lock = Lock()

    def is_configured(self) -> bool:
        return bool(self._sudo_username and self._sudo_password)

    def get_user(self, username: str) -> dict[str, Any] | None:
        if not self.is_configured():
            return None

        response = self._request(
            method="GET",
            path=f"/api/user/{username}",
            with_auth=True,
        )
        if response.status_code == 404:
            return None
        return response.json()

    def create_user(self, payload: dict[str, Any]) -> dict[str, Any] | None:
        if not self.is_configured():
            return None
        response = self._request(
            method="POST",
            path="/api/user",
            with_auth=True,
            json_data=payload,
        )
        return response.json()

    def update_user(self, username: str, payload: dict[str, Any]) -> dict[str, Any] | None:
        if not self.is_configured():
            return None
        response = self._request(
            method="PUT",
            path=f"/api/user/{username}",
            with_auth=True,
            json_data=payload,
        )
        return response.json()

    def _request(
        self,
        method: str,
        path: str,
        *,
        with_auth: bool,
        data: dict[str, Any] | None = None,
        json_data: dict[str, Any] | None = None,
    ) -> httpx.Response:
        headers: dict[str, str] = {}
        if with_auth:
            headers["Authorization"] = f"Bearer {self._get_admin_token()}"

        try:
            response = httpx.request(
                method=method,
                url=f"{self.base_url}{path}",
                headers=headers,
                data=data,
                json=json_data,
                timeout=self._timeout,
            )
        except httpx.HTTPError as exc:
            raise MarzbanUnavailableError("Failed to reach Marzban") from exc

        if response.status_code in (401, 403):
            if with_auth:
                self._invalidate_cached_token()
            raise MarzbanUnauthorizedError("Marzban credentials rejected")
        if response.status_code >= 500:
            raise MarzbanUnavailableError("Marzban returned a server error")
        if response.status_code >= 400 and response.status_code != 404:
            raise MarzbanError(f"Marzban request failed with status {response.status_code}")
        return response

    def _get_admin_token(self) -> str:
        with self._lock:
            if self._cached_token and self._cached_token.expires_at_ts > unix_timestamp_now():
                return self._cached_token.value

            response = self._request(
                method="POST",
                path="/api/admin/token",
                with_auth=False,
                data={"username": self._sudo_username, "password": self._sudo_password},
            )
            payload = response.json()
            token = payload["access_token"]
            self._cached_token = CachedToken(
                value=token,
                expires_at_ts=unix_timestamp_now() + self._token_cache_seconds,
            )
            return token

    def _invalidate_cached_token(self) -> None:
        with self._lock:
            self._cached_token = None


marzban_client = MarzbanClient()
