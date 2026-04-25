from __future__ import annotations

import httpx
import pytest
from fastapi import HTTPException

from app.core.config import settings
from app.services.auth_delivery_service import AuthDeliveryService


class _DummyResponse:
    def __init__(self, status_code: int) -> None:
        self.status_code = status_code

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise httpx.HTTPStatusError(
                message="error",
                request=httpx.Request("POST", "http://example.test"),
                response=httpx.Response(self.status_code),
            )


class _JsonDummyResponse(_DummyResponse):
    def __init__(self, status_code: int, payload: dict[str, object]) -> None:
        super().__init__(status_code)
        self._payload = payload

    def json(self) -> dict[str, object]:
        return self._payload


def test_http_provider_sends_otp_payload(monkeypatch: pytest.MonkeyPatch) -> None:
    previous_provider = settings.auth_provider
    previous_url = settings.auth_http_otp_url
    previous_token = settings.auth_http_otp_token
    previous_attempts = settings.auth_http_otp_max_attempts
    previous_backoff_ms = settings.auth_http_otp_retry_backoff_ms

    captured: dict[str, object] = {}

    class DummyClient:
        def __init__(self, *, timeout: float, trust_env: bool) -> None:
            captured["timeout"] = timeout
            captured["trust_env"] = trust_env

        def __enter__(self) -> "DummyClient":
            return self

        def __exit__(self, exc_type, exc, tb) -> None:
            _ = (exc_type, exc, tb)

        def post(self, url: str, *, json: dict[str, str], headers: dict[str, str]):
            captured["url"] = url
            captured["json"] = json
            captured["headers"] = headers
            return _DummyResponse(200)

    monkeypatch.setattr(httpx, "Client", DummyClient)
    settings.auth_provider = "http"
    settings.auth_http_otp_url = "https://otp-gateway.example/send"
    settings.auth_http_otp_token = "secret-token"
    settings.auth_http_otp_max_attempts = 1
    settings.auth_http_otp_retry_backoff_ms = 0

    issued = AuthDeliveryService().issue_code("user-1", "device-1", "challenge-1")

    assert issued.method == "otp"
    assert issued.delivery_hint == "OTP sent via configured delivery provider"
    assert len(issued.code) == settings.auth_otp_length
    assert captured["url"] == "https://otp-gateway.example/send"
    assert captured["json"] == {
        "login": "user-1",
        "code": issued.code,
        "device_id": "device-1",
    }
    assert captured["headers"] == {"Authorization": "Bearer secret-token"}
    assert captured["timeout"] == settings.auth_http_otp_timeout_seconds
    assert captured["trust_env"] is False

    settings.auth_provider = previous_provider
    settings.auth_http_otp_url = previous_url
    settings.auth_http_otp_token = previous_token
    settings.auth_http_otp_max_attempts = previous_attempts
    settings.auth_http_otp_retry_backoff_ms = previous_backoff_ms


def test_telegram_provider_sends_otp_to_resolved_chat(monkeypatch: pytest.MonkeyPatch) -> None:
    previous_provider = settings.auth_provider
    previous_token = settings.auth_telegram_bot_token
    previous_username = settings.auth_telegram_bot_username
    previous_api_base = settings.auth_telegram_api_base
    previous_limit = settings.auth_telegram_lookup_limit
    previous_timeout = settings.auth_telegram_send_timeout_seconds
    previous_trust_env = settings.auth_telegram_trust_env
    previous_link_base = settings.auth_magic_link_base_url

    captured: dict[str, object] = {}

    class DummyClient:
        def __init__(self, *, timeout: float, trust_env: bool) -> None:
            captured["timeout"] = timeout
            captured["trust_env"] = trust_env

        def __enter__(self) -> "DummyClient":
            return self

        def __exit__(self, exc_type, exc, tb) -> None:
            _ = (exc_type, exc, tb)

        def get(self, url: str, *, params: dict[str, object]):
            captured["updates_url"] = url
            captured["updates_params"] = params
            return _JsonDummyResponse(
                200,
                {
                    "ok": True,
                    "result": [
                        {
                            "update_id": 1,
                            "message": {
                                "from": {"username": "user_1"},
                                "chat": {"id": 777001},
                            },
                        }
                    ],
                },
            )

        def post(self, url: str, *, json: dict[str, object]):
            captured["send_url"] = url
            captured["send_json"] = json
            return _DummyResponse(200)

    monkeypatch.setattr(httpx, "Client", DummyClient)
    settings.auth_provider = "telegram"
    settings.auth_telegram_bot_token = "bot-token-1"
    settings.auth_telegram_bot_username = "arbuz_auth_bot"
    settings.auth_telegram_api_base = "https://api.telegram.org"
    settings.auth_telegram_lookup_limit = 77
    settings.auth_telegram_send_timeout_seconds = 9.5
    settings.auth_telegram_trust_env = True
    settings.auth_magic_link_base_url = "https://arbuzvpn.app/auth"

    issued = AuthDeliveryService().issue_code("@user_1", "device-1", "challenge-77")

    assert issued.method == "otp"
    assert len(issued.code) == settings.auth_otp_length
    assert issued.delivery_hint == "OTP sent to Telegram @user_1. Login link also sent."
    assert captured["updates_url"] == "https://api.telegram.org/botbot-token-1/getUpdates"
    assert captured["updates_params"] == {"timeout": 0, "limit": 77}
    assert captured["send_url"] == "https://api.telegram.org/botbot-token-1/sendMessage"
    assert captured["timeout"] == 9.5
    assert captured["trust_env"] is True
    send_json = captured["send_json"]
    assert isinstance(send_json, dict)
    assert send_json["chat_id"] == 777001
    assert "Arbuz VPN login code:" in str(send_json["text"])
    assert "challenge_id=challenge-77" in str(send_json["text"])
    assert issued.magic_link is not None
    assert "code=" in issued.magic_link

    settings.auth_provider = previous_provider
    settings.auth_telegram_bot_token = previous_token
    settings.auth_telegram_bot_username = previous_username
    settings.auth_telegram_api_base = previous_api_base
    settings.auth_telegram_lookup_limit = previous_limit
    settings.auth_telegram_send_timeout_seconds = previous_timeout
    settings.auth_telegram_trust_env = previous_trust_env
    settings.auth_magic_link_base_url = previous_link_base


def test_telegram_provider_returns_404_when_user_not_found(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    previous_provider = settings.auth_provider
    previous_token = settings.auth_telegram_bot_token
    previous_api_base = settings.auth_telegram_api_base

    class DummyClient:
        def __init__(self, *, timeout: float, trust_env: bool) -> None:
            _ = (timeout, trust_env)

        def __enter__(self) -> "DummyClient":
            return self

        def __exit__(self, exc_type, exc, tb) -> None:
            _ = (exc_type, exc, tb)

        def get(self, url: str, *, params: dict[str, object]):
            _ = (url, params)
            return _JsonDummyResponse(200, {"ok": True, "result": []})

        def post(self, url: str, *, json: dict[str, object]):
            _ = (url, json)
            return _DummyResponse(200)

    monkeypatch.setattr(httpx, "Client", DummyClient)
    settings.auth_provider = "telegram"
    settings.auth_telegram_bot_token = "bot-token-1"
    settings.auth_telegram_api_base = "https://api.telegram.org"

    with pytest.raises(HTTPException) as exc:
        AuthDeliveryService().issue_code("missing_user", "device-1", "challenge-1")
    assert exc.value.status_code == 404

    settings.auth_provider = previous_provider
    settings.auth_telegram_bot_token = previous_token
    settings.auth_telegram_api_base = previous_api_base


def test_http_provider_returns_503_on_delivery_error(monkeypatch: pytest.MonkeyPatch) -> None:
    previous_provider = settings.auth_provider
    previous_url = settings.auth_http_otp_url
    previous_token = settings.auth_http_otp_token
    previous_attempts = settings.auth_http_otp_max_attempts
    previous_backoff_ms = settings.auth_http_otp_retry_backoff_ms

    class DummyClient:
        def __init__(self, *, timeout: float, trust_env: bool) -> None:
            _ = (timeout, trust_env)

        def __enter__(self) -> "DummyClient":
            return self

        def __exit__(self, exc_type, exc, tb) -> None:
            _ = (exc_type, exc, tb)

        def post(self, url: str, *, json: dict[str, str], headers: dict[str, str]):
            _ = (url, json, headers)
            return _DummyResponse(502)

    monkeypatch.setattr(httpx, "Client", DummyClient)
    settings.auth_provider = "http"
    settings.auth_http_otp_url = "https://otp-gateway.example/send"
    settings.auth_http_otp_token = ""
    settings.auth_http_otp_max_attempts = 1
    settings.auth_http_otp_retry_backoff_ms = 0

    with pytest.raises(HTTPException) as exc:
        AuthDeliveryService().issue_code("user-1", "device-1", "challenge-1")
    assert exc.value.status_code == 503

    settings.auth_provider = previous_provider
    settings.auth_http_otp_url = previous_url
    settings.auth_http_otp_token = previous_token
    settings.auth_http_otp_max_attempts = previous_attempts
    settings.auth_http_otp_retry_backoff_ms = previous_backoff_ms


def test_http_provider_retries_and_succeeds(monkeypatch: pytest.MonkeyPatch) -> None:
    previous_provider = settings.auth_provider
    previous_url = settings.auth_http_otp_url
    previous_token = settings.auth_http_otp_token
    previous_attempts = settings.auth_http_otp_max_attempts
    previous_backoff_ms = settings.auth_http_otp_retry_backoff_ms

    call_count = 0

    class DummyClient:
        def __init__(self, *, timeout: float, trust_env: bool) -> None:
            _ = (timeout, trust_env)

        def __enter__(self) -> "DummyClient":
            return self

        def __exit__(self, exc_type, exc, tb) -> None:
            _ = (exc_type, exc, tb)

        def post(self, url: str, *, json: dict[str, str], headers: dict[str, str]):
            nonlocal call_count
            _ = (url, json, headers)
            call_count += 1
            if call_count == 1:
                return _DummyResponse(502)
            return _DummyResponse(200)

    monkeypatch.setattr(httpx, "Client", DummyClient)
    settings.auth_provider = "http"
    settings.auth_http_otp_url = "https://otp-gateway.example/send"
    settings.auth_http_otp_token = ""
    settings.auth_http_otp_max_attempts = 2
    settings.auth_http_otp_retry_backoff_ms = 0

    issued = AuthDeliveryService().issue_code("user-1", "device-1", "challenge-1")

    assert issued.method == "otp"
    assert call_count == 2

    settings.auth_provider = previous_provider
    settings.auth_http_otp_url = previous_url
    settings.auth_http_otp_token = previous_token
    settings.auth_http_otp_max_attempts = previous_attempts
    settings.auth_http_otp_retry_backoff_ms = previous_backoff_ms
