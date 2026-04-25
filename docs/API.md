# API Draft

## Public API (`/api/v1`)

- `POST /auth/start`
- `POST /auth/verify`
- `POST /auth/refresh`
- `POST /auth/logout`
- `POST /auth/logout-all`
- `GET /me`
- `GET /subscription`
- `GET /configs`
- `POST /support/request`

## Internal API (`/internal`)

- `POST /admin/provision`
- `POST /admin/extend`
- `POST /maintenance/cleanup-auth`

Internal headers:
- `X-API-Key: <internal_admin_api_key>`
- `Idempotency-Key: <unique-request-key>`

## Auth

Authenticated endpoints require `Authorization: Bearer <access_token>`.
All responses include `X-Request-ID`.

Current development auth behavior:
- `POST /auth/start` stores a hashed OTP challenge in DB
- `AUTH_PROVIDER=dev_fixed` accepts fixed OTP from `AUTH_DEFAULT_OTP_CODE`
- `AUTH_PROVIDER=console` prints a generated OTP to backend logs
- `AUTH_PROVIDER=http` posts generated OTP to `AUTH_HTTP_OTP_URL`
- `AUTH_PROVIDER=telegram` sends OTP via Telegram Bot API (`AUTH_TELEGRAM_BOT_TOKEN`)
- `/auth/start` can include `magic_link` with `challenge_id` and `code` query params for link-based sign-in
- verify attempts per challenge are limited by `AUTH_VERIFY_MAX_ATTEMPTS`
- resend/start for the same login is throttled by `AUTH_RESEND_COOLDOWN_SECONDS`
- for local contract verification, use `make backend-smoke-http` (mock OTP gateway)
- for local console mode e2e, use `make backend-smoke-console`
- for real provider compatibility check, use `make otp-contract-check`
- `POST /auth/refresh` validates refresh token hash from DB and returns a new access token
- `POST /auth/logout` revokes the current bearer session and optional refresh token
- `POST /auth/logout-all` revokes all sessions for the authenticated user
- auth endpoints are rate-limited in-process per client IP

Telegram OTP provider notes:
- before first OTP, user must start bot dialog (`/start`) so updates include their chat id
- login value can be either `username` or `@username`
- bot message includes both OTP and one-tap login link

## Notes

- Subscription and configs can sync from Marzban when `MARZBAN_SUDO_*` env vars are configured.
- Internal `provision` and `extend` endpoints also attempt Marzban synchronization.
- If Marzban is not configured yet, `/configs` returns a development placeholder value.
- Errors use a stable shape: `code`, `message`, `request_id`, `details`.
