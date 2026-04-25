#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT/backend/bff"

if [[ -f "$PROJECT_ROOT/infra/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/infra/.env"
  set +a
fi

OTP_GATEWAY_HOST="${OTP_GATEWAY_HOST:-127.0.0.1}"
OTP_GATEWAY_PORT="${OTP_GATEWAY_PORT:-8010}"
OTP_GATEWAY_FILE="${OTP_GATEWAY_FILE:-/tmp/arbuz_otp_gateway.json}"
OTP_GATEWAY_TOKEN="${AUTH_HTTP_OTP_TOKEN:-}"
OTP_GATEWAY_URL="${AUTH_HTTP_OTP_URL:-http://$OTP_GATEWAY_HOST:$OTP_GATEWAY_PORT/send}"
BFF_HOST="${BFF_HOST:-127.0.0.1}"
BFF_PORT="${BFF_PORT:-8002}"
BFF_BASE_URL="http://$BFF_HOST:$BFF_PORT"

export PYTHONPATH=.
export AUTH_PROVIDER="http"
export AUTH_HTTP_OTP_URL="$OTP_GATEWAY_URL"
export AUTH_HTTP_OTP_TOKEN="$OTP_GATEWAY_TOKEN"
export MARZBAN_SUDO_USERNAME="${MARZBAN_SUDO_USERNAME:-}"
export MARZBAN_SUDO_PASSWORD="${MARZBAN_SUDO_PASSWORD:-}"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY ftp_proxy FTP_PROXY
export NO_PROXY="127.0.0.1,localhost"
export no_proxy="127.0.0.1,localhost"

if command -v getent >/dev/null 2>&1; then
  if [[ "${DATABASE_URL:-}" == *"@postgres:"* ]] && ! getent hosts postgres >/dev/null 2>&1; then
    export DATABASE_URL="sqlite+pysqlite:///./arbuz.db"
    echo "smoke_notice: postgres host not reachable, fallback DATABASE_URL=$DATABASE_URL"
  fi
fi

rm -f /tmp/arbuz_otp_gateway.log /tmp/arbuz_bff_migrate.log /tmp/arbuz_bff_smoke_http.log

for cmd in alembic uvicorn curl python; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "smoke_error: missing required command '$cmd'"
    exit 1
  fi
done

OTP_GATEWAY_PID=""
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$OTP_GATEWAY_PID" ]]; then
    kill "$OTP_GATEWAY_PID" >/dev/null 2>&1 || true
  fi
}

on_error() {
  local exit_code=$?
  echo "smoke_error: backend http smoke failed (exit $exit_code)"
  echo
  if [[ -f /tmp/arbuz_otp_gateway.log ]]; then
    echo "otp_gateway_log:"
    cat /tmp/arbuz_otp_gateway.log || true
    echo
  fi
  if [[ -f /tmp/arbuz_bff_migrate.log ]]; then
    echo "migration_log:"
    cat /tmp/arbuz_bff_migrate.log || true
    echo
  fi
  if [[ -f /tmp/arbuz_bff_smoke_http.log ]]; then
    echo "server_log:"
    cat /tmp/arbuz_bff_smoke_http.log || true
    echo
  fi
  cleanup
  exit "$exit_code"
}
trap on_error ERR
trap cleanup EXIT

python "$PROJECT_ROOT/scripts/otp_mock_gateway.py" \
  --host "$OTP_GATEWAY_HOST" \
  --port "$OTP_GATEWAY_PORT" \
  --out "$OTP_GATEWAY_FILE" \
  --token "$OTP_GATEWAY_TOKEN" >/tmp/arbuz_otp_gateway.log 2>&1 &
OTP_GATEWAY_PID=$!

sleep 1

OTP_HEALTH=$(curl -sS "http://$OTP_GATEWAY_HOST:$OTP_GATEWAY_PORT/health")
printf '%s' "$OTP_HEALTH" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('status') == 'ok', d"

alembic upgrade head >/tmp/arbuz_bff_migrate.log 2>&1

uvicorn app.main:app --host "$BFF_HOST" --port "$BFF_PORT" >/tmp/arbuz_bff_smoke_http.log 2>&1 &
SERVER_PID=$!

sleep 2

echo "health:"
HEALTH_JSON=$(curl -sS "$BFF_BASE_URL/health")
echo "$HEALTH_JSON"
printf '%s' "$HEALTH_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('status')=='ok', d"
echo -e "\n"

AUTH_START_JSON=$(curl -sS -X POST "$BFF_BASE_URL/api/v1/auth/start" \
  -H "Content-Type: application/json" \
  -d '{"login":"manual-user","device_id":"linux-dev"}')
echo "auth_start:"
echo "$AUTH_START_JSON"
echo -e "\n"

CHALLENGE_ID=$(printf '%s' "$AUTH_START_JSON" | python -c "import json,sys; print(json.load(sys.stdin).get('challenge_id',''))")
if [[ -z "$CHALLENGE_ID" ]]; then
  echo "smoke_error: auth_start did not return challenge_id"
  exit 1
fi

OTP_CODE=$(python - "$OTP_GATEWAY_FILE" <<'PY'
import json
import sys
import time

path = sys.argv[1]
login = "manual-user"

for _ in range(20):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        data = {}
    if login in data and data[login].get("code"):
        print(data[login]["code"])
        break
    time.sleep(0.2)
else:
    print("")
PY
)

if [[ -z "$OTP_CODE" ]]; then
  echo "smoke_error: mock otp gateway did not receive code"
  exit 1
fi

echo "mock_otp_received:"
echo "{\"login\":\"manual-user\",\"code\":\"$OTP_CODE\"}"
echo -e "\n"

AUTH_VERIFY_JSON=$(curl -sS -X POST "$BFF_BASE_URL/api/v1/auth/verify" \
  -H "Content-Type: application/json" \
  -d "{\"challenge_id\":\"$CHALLENGE_ID\",\"code\":\"$OTP_CODE\",\"device_id\":\"linux-dev\"}")
echo "auth_verify:"
echo "$AUTH_VERIFY_JSON"
echo -e "\n"

ACCESS_TOKEN=$(printf '%s' "$AUTH_VERIFY_JSON" | python -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")
REFRESH_TOKEN=$(printf '%s' "$AUTH_VERIFY_JSON" | python -c "import json,sys; print(json.load(sys.stdin).get('refresh_token',''))")
if [[ -z "$ACCESS_TOKEN" || -z "$REFRESH_TOKEN" ]]; then
  echo "smoke_error: auth_verify did not return tokens"
  exit 1
fi

echo "me:"
ME_JSON=$(curl -sS "$BFF_BASE_URL/api/v1/me" -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$ME_JSON"
printf '%s' "$ME_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('user_id')=='manual-user', d"
echo -e "\n"

echo "subscription:"
SUBSCRIPTION_JSON=$(curl -sS "$BFF_BASE_URL/api/v1/subscription" -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$SUBSCRIPTION_JSON"
printf '%s' "$SUBSCRIPTION_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert 'is_active' in d and 'days_left' in d, d"
echo -e "\n"

echo "configs:"
CONFIGS_JSON=$(curl -sS "$BFF_BASE_URL/api/v1/configs" -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$CONFIGS_JSON"
printf '%s' "$CONFIGS_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d.get('items'), list) and len(d['items'])>0, d"
echo -e "\n"

echo "support:"
SUPPORT_JSON=$(curl -sS -X POST "$BFF_BASE_URL/api/v1/support/request" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"subject":"Need help with setup","message":"HTTP OTP smoke run from local script"}')
echo "$SUPPORT_JSON"
printf '%s' "$SUPPORT_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('accepted') is True and d.get('ticket_id'), d"
echo -e "\n"

echo "logout:"
LOGOUT_JSON=$(curl -sS -X POST "$BFF_BASE_URL/api/v1/auth/logout" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}")
echo "$LOGOUT_JSON"
printf '%s' "$LOGOUT_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('success') is True, d"
echo -e "\n"

echo "me_after_logout:"
ME_AFTER_LOGOUT_JSON=$(curl -sS "$BFF_BASE_URL/api/v1/me" -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$ME_AFTER_LOGOUT_JSON"
printf '%s' "$ME_AFTER_LOGOUT_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('code')=='http_error' and 'Session is not active' in d.get('message',''), d"
echo -e "\n"

echo "smoke_http_done: OK"
