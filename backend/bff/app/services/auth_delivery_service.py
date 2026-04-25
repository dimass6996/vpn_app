from __future__ import annotations

from dataclasses import dataclass
import logging
import time
from urllib.parse import urlencode

import httpx
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import generate_otp_code
from app.db.models.telegram_chat_link import TelegramChatLink

logger = logging.getLogger(__name__)


@dataclass
class IssuedCode:
    method: str
    code: str
    delivery_hint: str
    magic_link: str | None = None


class AuthProvider:
    def issue_code(
        self,
        login: str,
        device_id: str,
        challenge_id: str,
        db: Session | None = None,
    ) -> IssuedCode:
        raise NotImplementedError


class DevFixedCodeProvider(AuthProvider):
    def issue_code(
        self,
        login: str,
        device_id: str,
        challenge_id: str,
        db: Session | None = None,
    ) -> IssuedCode:
        _ = (login, device_id, challenge_id, db)
        return IssuedCode(
            method="otp",
            code=settings.auth_default_otp_code,
            delivery_hint="development fixed code enabled",
        )


class ConsoleOtpProvider(AuthProvider):
    def issue_code(
        self,
        login: str,
        device_id: str,
        challenge_id: str,
        db: Session | None = None,
    ) -> IssuedCode:
        _ = (device_id, challenge_id, db)
        code = generate_otp_code(settings.auth_otp_length)
        print(f"[arbuz-auth] login={login} otp={code}")
        return IssuedCode(
            method="otp",
            code=code,
            delivery_hint="OTP written to backend console log",
        )


class HttpOtpProvider(AuthProvider):
    def issue_code(
        self,
        login: str,
        device_id: str,
        challenge_id: str,
        db: Session | None = None,
    ) -> IssuedCode:
        _ = db
        code = generate_otp_code(settings.auth_otp_length)
        if not settings.auth_http_otp_url:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="HTTP OTP provider URL is not configured",
            )

        headers: dict[str, str] = {}
        if settings.auth_http_otp_token:
            headers["Authorization"] = f"Bearer {settings.auth_http_otp_token}"

        payload = {
            "login": login,
            "code": code,
            "device_id": device_id,
        }
        max_attempts = max(1, settings.auth_http_otp_max_attempts)
        last_error: Exception | None = None

        for attempt in range(1, max_attempts + 1):
            try:
                with httpx.Client(
                    timeout=settings.auth_http_otp_timeout_seconds,
                    trust_env=False,
                ) as client:
                    response = client.post(
                        settings.auth_http_otp_url,
                        json=payload,
                        headers=headers,
                    )
                    response.raise_for_status()
                break
            except Exception as exc:
                last_error = exc
                if attempt < max_attempts and settings.auth_http_otp_retry_backoff_ms > 0:
                    time.sleep(settings.auth_http_otp_retry_backoff_ms / 1000)
        else:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OTP delivery provider is unavailable",
            ) from last_error

        return IssuedCode(
            method="otp",
            code=code,
            delivery_hint="OTP sent via configured delivery provider",
        )


class TelegramOtpProvider(AuthProvider):
    def issue_code(
        self,
        login: str,
        device_id: str,
        challenge_id: str,
        db: Session | None = None,
    ) -> IssuedCode:
        _ = device_id
        bot_token = settings.auth_telegram_bot_token.strip()
        if not bot_token:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Telegram OTP provider is not configured",
            )

        target_username = login.strip().lstrip("@")
        if not target_username:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Telegram username is required",
            )

        code = generate_otp_code(settings.auth_otp_length)
        magic_link = _build_magic_link(challenge_id=challenge_id, code=code)
        api_base = settings.auth_telegram_api_base.rstrip("/")
        updates_url = f"{api_base}/bot{bot_token}/getUpdates"
        send_url = f"{api_base}/bot{bot_token}/sendMessage"

        try:
            with httpx.Client(
                timeout=settings.auth_telegram_send_timeout_seconds,
                trust_env=settings.auth_telegram_trust_env,
            ) as client:
                chat_id = self._find_chat_id(db=db, client=client, updates_url=updates_url, username=target_username)

                message_text = (
                    "Arbuz VPN login code: "
                    f"{code}\n"
                    "Code valid for "
                    f"{settings.auth_challenge_ttl_minutes} minutes."
                )
                if magic_link:
                    message_text = (
                        f"{message_text}\n\n"
                        "One-tap login link:\n"
                        f"{magic_link}"
                    )
                send_response = client.post(
                    send_url,
                    json={
                        "chat_id": chat_id,
                        "text": message_text,
                        "disable_web_page_preview": True,
                    },
                )
                send_response.raise_for_status()
        except HTTPException:
            raise
        except Exception as exc:
            logger.exception("Telegram OTP provider failed for login=%s", login)
            detail = "Telegram OTP provider is unavailable"
            if settings.app_env.lower() == "dev":
                detail = f"{detail}: {type(exc).__name__}: {exc}"
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=detail,
            ) from exc

        return IssuedCode(
            method="otp",
            code=code,
            delivery_hint=f"OTP sent to Telegram @{target_username}. Login link also sent.",
            magic_link=magic_link,
        )

    def _find_chat_id(
        self,
        *,
        db: Session | None,
        client: httpx.Client,
        updates_url: str,
        username: str,
    ) -> int:
        cached_chat_id = self._chat_id_from_db(db=db, username=username)
        if cached_chat_id is not None:
            return cached_chat_id

        updates_response = client.get(
            updates_url,
            params={
                "timeout": 0,
                "limit": max(1, settings.auth_telegram_lookup_limit),
            },
        )
        updates_response.raise_for_status()
        updates_payload = updates_response.json()
        results = updates_payload.get("result", [])

        target_username_lower = username.lower()
        chat_id: int | None = None
        for update in reversed(results):
            message = update.get("message") or update.get("edited_message") or {}
            from_user = message.get("from") or {}
            tg_username = str(from_user.get("username", "")).lower()
            if tg_username == target_username_lower:
                chat = message.get("chat") or {}
                chat_id = self._coerce_chat_id(chat.get("id"))
                if chat_id is not None:
                    break

        if chat_id is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=(
                    "Telegram user not found in bot updates. "
                    "Open @"
                    f"{settings.auth_telegram_bot_username or 'bot'} "
                    "and send /start first"
                ),
            )
        self._save_chat_id(db=db, username=username, chat_id=chat_id)
        return chat_id

    def _chat_id_from_db(self, *, db: Session | None, username: str) -> int | None:
        if db is None:
            return None
        normalized = username.strip().lower()
        if not normalized:
            return None
        link = db.scalar(
            select(TelegramChatLink).where(
                TelegramChatLink.telegram_username == normalized
            )
        )
        if link is None:
            return None
        return self._coerce_chat_id(link.chat_id)

    def _save_chat_id(self, *, db: Session | None, username: str, chat_id: int) -> None:
        if db is None:
            return
        normalized = username.strip().lower()
        if not normalized:
            return
        link = db.scalar(
            select(TelegramChatLink).where(
                TelegramChatLink.telegram_username == normalized
            )
        )
        if link is None:
            link = TelegramChatLink(
                telegram_username=normalized,
                chat_id=chat_id,
            )
            db.add(link)
            return
        link.chat_id = chat_id

    def _coerce_chat_id(self, raw: object) -> int | None:
        if isinstance(raw, int):
            return raw
        if isinstance(raw, str):
            trimmed = raw.strip()
            if trimmed and trimmed.lstrip("-").isdigit():
                return int(trimmed)
        return None


def _build_magic_link(challenge_id: str, code: str) -> str | None:
    base_url = settings.auth_magic_link_base_url.strip()
    if not base_url:
        return None
    separator = "&" if "?" in base_url else "?"
    query = urlencode({"challenge_id": challenge_id, "code": code})
    return f"{base_url}{separator}{query}"


class AuthDeliveryService:
    def __init__(self) -> None:
        self._providers: dict[str, AuthProvider] = {
            "dev_fixed": DevFixedCodeProvider(),
            "console": ConsoleOtpProvider(),
            "http": HttpOtpProvider(),
            "telegram": TelegramOtpProvider(),
        }

    def issue_code(
        self,
        login: str,
        device_id: str,
        challenge_id: str,
        db: Session | None = None,
    ) -> IssuedCode:
        provider = self._providers.get(settings.auth_provider)
        if provider is None:
            provider = self._providers["dev_fixed"]
        return provider.issue_code(login, device_id, challenge_id, db=db)


auth_delivery_service = AuthDeliveryService()
