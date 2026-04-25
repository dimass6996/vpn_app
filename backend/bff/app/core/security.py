from datetime import UTC, datetime, timedelta
import hashlib
import secrets

from jose import JWTError, jwt

from app.core.config import settings


class TokenError(ValueError):
    pass


def utcnow() -> datetime:
    return datetime.utcnow()


def unix_timestamp_now() -> int:
    return int(datetime.now(UTC).timestamp())


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def hash_otp_code(code: str) -> str:
    return hashlib.sha256(f"otp:{code}".encode("utf-8")).hexdigest()


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def generate_otp_code(length: int) -> str:
    digits = "0123456789"
    return "".join(secrets.choice(digits) for _ in range(length))


def create_access_token(subject: str, session_id: str) -> tuple[str, datetime]:
    expires_at = utcnow() + timedelta(minutes=settings.access_token_expire_minutes)
    exp_unix = unix_timestamp_now() + settings.access_token_expire_minutes * 60
    payload = {
        "sub": subject,
        "sid": session_id,
        "type": "access",
        "exp": exp_unix,
    }
    token = jwt.encode(payload, settings.secret_key, algorithm=settings.jwt_algorithm)
    return token, expires_at


def decode_access_token(token: str) -> dict[str, str]:
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.jwt_algorithm])
    except JWTError as exc:
        raise TokenError("Invalid token") from exc

    if payload.get("type") != "access":
        raise TokenError("Unsupported token type")
    if not payload.get("sub") or not payload.get("sid"):
        raise TokenError("Incomplete token payload")
    return {"sub": payload["sub"], "sid": payload["sid"]}
