from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    app_env: str = "dev"
    secret_key: str = "change-me"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 30
    auth_challenge_ttl_minutes: int = 10
    auth_provider: str = "dev_fixed"
    auth_default_otp_code: str = "000000"
    auth_otp_length: int = 6
    auth_verify_max_attempts: int = 5
    auth_resend_cooldown_seconds: int = 30
    auth_http_otp_url: str = ""
    auth_http_otp_token: str = ""
    auth_http_otp_timeout_seconds: float = 5.0
    auth_http_otp_max_attempts: int = 2
    auth_http_otp_retry_backoff_ms: int = 150
    auth_telegram_bot_token: str = ""
    auth_telegram_bot_username: str = ""
    auth_telegram_api_base: str = "https://api.telegram.org"
    auth_telegram_lookup_limit: int = 100
    auth_telegram_send_timeout_seconds: float = 8.0
    auth_telegram_trust_env: bool = True
    auth_magic_link_base_url: str = "https://arbuzvpn.app/auth"
    auth_rate_limit_attempts: int = 5
    auth_rate_limit_window_seconds: int = 60
    rate_limit_backend: str = "memory"
    internal_admin_api_key: str = "change-internal-admin-key"

    database_url: str = "sqlite+pysqlite:///./arbuz.db"
    redis_url: str = "redis://redis:6379/0"

    marzban_base_url: str = "http://127.0.0.1:8000"
    marzban_sudo_username: str = ""
    marzban_sudo_password: str = ""
    marzban_request_timeout_seconds: float = 10.0
    marzban_admin_token_cache_seconds: int = 300
    default_provision_days: int = 30


settings = Settings()
