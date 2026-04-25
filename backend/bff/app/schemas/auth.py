from pydantic import BaseModel, Field, field_validator


class AuthStartRequest(BaseModel):
    login: str = Field(min_length=3, max_length=128)
    device_id: str = "unknown-device"

    @field_validator("login")
    @classmethod
    def normalize_login(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("Login must not be blank")
        return normalized


class AuthStartResponse(BaseModel):
    challenge_id: str
    method: str
    delivery_hint: str | None = None
    magic_link: str | None = None


class AuthVerifyRequest(BaseModel):
    challenge_id: str
    code: str = Field(min_length=1, max_length=12)
    device_id: str = "unknown-device"

    @field_validator("code")
    @classmethod
    def normalize_code(cls, value: str) -> str:
        normalized = value.strip()
        if len(normalized) < 4:
            raise ValueError("Code must contain at least 4 characters")
        return normalized


class TokenPairResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshRequest(BaseModel):
    refresh_token: str


class AccessTokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int


class LogoutRequest(BaseModel):
    refresh_token: str | None = None


class LogoutResponse(BaseModel):
    success: bool
    revoked_sessions: int
