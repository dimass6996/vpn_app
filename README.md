# Arbuz VPN Monorepo

MVP project bootstrap for:
- Mobile app: Flutter
- Backend BFF: FastAPI
- Data: PostgreSQL + Redis

## Repository Layout

```text
mobile/app/              Flutter app scaffold
backend/bff/             FastAPI BFF
infra/                   Local docker-compose and env template
docs/                    Architecture and API notes
```

## Quick Start (Backend)

1. Copy env template:
```bash
cp infra/.env.example infra/.env
```
2. Start local services:
```bash
docker compose -f infra/docker-compose.yml --env-file infra/.env up --build
```
3. Open API docs:
```text
http://localhost:8001/docs
```

The backend container runs `alembic upgrade head` before starting `uvicorn`.

## Dev Commands

```bash
make env-init
make backend-up
make backend-logs
make backend-smoke
make backend-smoke-http
make backend-smoke-console
make otp-contract-check
make marzban-probe
make marzban-upsert-user
make mobile-test
make mobile-check
make dev-check
make mobile-linux
make mobile-web
```

If Docker is unavailable on the host, run the API smoke test directly:
```bash
python -m pip install -r backend/bff/requirements.txt
make backend-smoke
```
`backend-smoke` applies `alembic upgrade head` before running the checks.
It also validates expected response shapes and fails on regressions.
Smoke scripts auto-load environment from `infra/.env` when present.
If `DATABASE_URL` points to docker host `postgres` but host DNS is unavailable, smoke scripts auto-fallback to local SQLite.
`backend-smoke-http` runs the same flow with `AUTH_PROVIDER=http` and a local mock OTP gateway.
By default `backend-smoke-http` uses `BFF_PORT=8002` to avoid clashes with an already running API on `8001`.
`backend-smoke-console` runs the same flow with `AUTH_PROVIDER=console` and auto-reads OTP from backend log (`SMOKE_LOGIN` configurable).
`otp-contract-check` sends a test OTP payload to `AUTH_HTTP_OTP_URL` and verifies a `2xx` provider response.
`marzban-probe` checks Marzban credentials/token and prints user summary for `MARZBAN_PROBE_USERNAME` (default `manual-user`).
`marzban-upsert-user` creates or updates a Marzban user (`MARZBAN_TARGET_USERNAME`, default `manual-user`) and prints `subscription_url`.
`mobile-test` runs Flutter tests with proxy env vars unset to avoid localhost test-shell issues.

## MVP Scope Implemented

- FastAPI app skeleton
- SQLite-backed dev persistence by default
- JWT access tokens + refresh session storage
- Auth provider abstraction with hashed OTP challenges in DB
- Logout, logout-all and expired auth data cleanup flows
- Audit logging table and service
- In-memory auth rate limiting for dev
- Redis-ready rate limit backend switch via config
- Stable error payloads and per-request IDs
- Basic HTTP request logging with timing
- Internal admin API key + idempotency keys
- Marzban-backed read and write integration with safe fallback
- API v1 routes:
  - `POST /api/v1/auth/start`
  - `POST /api/v1/auth/verify`
  - `POST /api/v1/auth/refresh`
  - `POST /api/v1/auth/logout`
  - `POST /api/v1/auth/logout-all`
  - `GET /api/v1/me`
  - `GET /api/v1/subscription`
  - `GET /api/v1/configs`
  - `POST /api/v1/support/request`
- Internal admin routes:
  - `POST /internal/admin/provision`
  - `POST /internal/admin/extend`
- Mobile controller tests for bootstrap, restore, refresh and logout flows

This is a bootstrap, not a production-complete implementation yet.

## Current Auth Flow

- `POST /api/v1/auth/start` creates an OTP challenge in the database
- `AUTH_PROVIDER=dev_fixed` uses fixed OTP from `AUTH_DEFAULT_OTP_CODE` (dev only)
- `AUTH_PROVIDER=console` writes generated OTP to backend logs (recommended local mode)
- `AUTH_PROVIDER=http` sends generated OTP to `AUTH_HTTP_OTP_URL` (Bearer token optional)
- `AUTH_PROVIDER=telegram` sends generated OTP to Telegram user via Bot API (`AUTH_TELEGRAM_BOT_TOKEN`)
- when Telegram provider is active, `/auth/start` also returns `magic_link` and bot message includes the same link
- OTP verify attempts are limited by `AUTH_VERIFY_MAX_ATTEMPTS`
- OTP resend is limited by `AUTH_RESEND_COOLDOWN_SECONDS`
- `POST /api/v1/auth/verify` creates a user and auth session if needed
- authenticated endpoints expect `Authorization: Bearer <access_token>`
- auth endpoints are rate-limited per client IP in-process

For Telegram OTP mode:
- user must open `https://t.me/<AUTH_TELEGRAM_BOT_USERNAME>` and send `/start` at least once
- login can be passed as `username` or `@username`
- backend resolves chat by scanning `getUpdates` and then sends OTP via `sendMessage`
- `AUTH_MAGIC_LINK_BASE_URL` controls login-link host/scheme (`?challenge_id=...&code=...` is appended)

## Internal Admin Contract

- internal endpoints require `X-API-Key`
- mutation endpoints also require `Idempotency-Key`
- maintenance endpoint available at `POST /internal/maintenance/cleanup-auth`
- `provision/extend` attempt to sync Marzban first, then persist BFF state

## Android VPN Runtime (In Progress)

- `/api/v1/configs` now returns:
  - `subscription` (primary personal URL)
  - `sing-box-subscription` (same URL with `format=sing-box`)
- Mobile VPN toggle uses `sing-box-subscription` first, fallback to `subscription`.
- Android contains `ArbuzVpnService` (`VpnService`) and channel `arbuz.vpn/control`.
- Service bootstraps TUN and tries to launch `sing-box` core binary.
- Expected binary locations:
  - app private files dir: `<files>/sing-box`
  - dev fallback: `/data/local/tmp/sing-box`
- Helper command to push binary to connected device:
  - `make mobile-android-push-singbox` (or set `SINGBOX_BINARY_PATH=/abs/path/to/binary`)
- App now tries to auto-copy binary from `/data/local/tmp/sing-box` to `<files>/sing-box` on first connect.
