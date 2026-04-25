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

export PYTHONPATH=.
export MARZBAN_SUDO_USERNAME="${MARZBAN_SUDO_USERNAME:-}"
export MARZBAN_SUDO_PASSWORD="${MARZBAN_SUDO_PASSWORD:-}"

if command -v getent >/dev/null 2>&1; then
  if [[ "${DATABASE_URL:-}" == *"@postgres:"* ]] && ! getent hosts postgres >/dev/null 2>&1; then
    export DATABASE_URL="sqlite+pysqlite:///./arbuz.db"
    echo "smoke_notice: postgres host not reachable, fallback DATABASE_URL=$DATABASE_URL"
  fi
fi

rm -f /tmp/arbuz_bff_migrate.log /tmp/arbuz_bff_smoke.log

for cmd in alembic uvicorn curl python; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "smoke_error: missing required command '$cmd'"
    exit 1
  fi
done

on_error() {
  local exit_code=$?
  echo "smoke_error: backend smoke failed (exit $exit_code)"
  echo
  if [[ -f /tmp/arbuz_bff_migrate.log ]]; then
    echo "migration_log:"
    cat /tmp/arbuz_bff_migrate.log || true
    echo
  fi
  if [[ -f /tmp/arbuz_bff_smoke.log ]]; then
    echo "server_log:"
    cat /tmp/arbuz_bff_smoke.log || true
    echo
  fi
  exit "$exit_code"
}
trap on_error ERR

alembic upgrade head >/tmp/arbuz_bff_migrate.log 2>&1

uvicorn app.main:app --host 127.0.0.1 --port 8001 >/tmp/arbuz_bff_smoke.log 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 2

echo "health:"
HEALTH_JSON=$(curl -sS http://127.0.0.1:8001/health)
echo "$HEALTH_JSON"
printf '%s' "$HEALTH_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('status')=='ok', d"
echo -e "\n"

AUTH_START_JSON=$(curl -sS -X POST http://127.0.0.1:8001/api/v1/auth/start \
  -H "Content-Type: application/json" \
  -d '{"login":"manual-user","device_id":"linux-dev"}')
echo "auth_start:"
echo "$AUTH_START_JSON"
echo -e "\n"

CHALLENGE_ID=$(printf '%s' "$AUTH_START_JSON" | python -c "import json,sys; print(json.load(sys.stdin).get('challenge_id',''))")
if [[ -z "$CHALLENGE_ID" ]]; then
  echo "smoke_error: auth_start did not return challenge_id"
  echo "server_log:"
  cat /tmp/arbuz_bff_smoke.log || true
  echo
  echo "migration_log:"
  cat /tmp/arbuz_bff_migrate.log || true
  exit 1
fi

AUTH_VERIFY_JSON=$(curl -sS -X POST http://127.0.0.1:8001/api/v1/auth/verify \
  -H "Content-Type: application/json" \
  -d "{\"challenge_id\":\"$CHALLENGE_ID\",\"code\":\"000000\",\"device_id\":\"linux-dev\"}")
echo "auth_verify:"
echo "$AUTH_VERIFY_JSON"
echo -e "\n"

ACCESS_TOKEN=$(printf '%s' "$AUTH_VERIFY_JSON" | python -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))")
REFRESH_TOKEN=$(printf '%s' "$AUTH_VERIFY_JSON" | python -c "import json,sys; print(json.load(sys.stdin).get('refresh_token',''))")
if [[ -z "$ACCESS_TOKEN" || -z "$REFRESH_TOKEN" ]]; then
  echo "smoke_error: auth_verify did not return tokens"
  echo "server_log:"
  cat /tmp/arbuz_bff_smoke.log || true
  exit 1
fi

echo "me:"
ME_JSON=$(curl -sS http://127.0.0.1:8001/api/v1/me -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$ME_JSON"
printf '%s' "$ME_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('user_id')=='manual-user', d"
echo -e "\n"

echo "subscription:"
SUBSCRIPTION_JSON=$(curl -sS http://127.0.0.1:8001/api/v1/subscription -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$SUBSCRIPTION_JSON"
printf '%s' "$SUBSCRIPTION_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert 'is_active' in d and 'days_left' in d, d"
echo -e "\n"

echo "configs:"
CONFIGS_JSON=$(curl -sS http://127.0.0.1:8001/api/v1/configs -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$CONFIGS_JSON"
printf '%s' "$CONFIGS_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert isinstance(d.get('items'), list) and len(d['items'])>0, d"
echo -e "\n"

echo "support:"
SUPPORT_JSON=$(curl -sS -X POST http://127.0.0.1:8001/api/v1/support/request \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"subject":"Need help with setup","message":"Smoke run from local script"}')
echo "$SUPPORT_JSON"
printf '%s' "$SUPPORT_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('accepted') is True and d.get('ticket_id'), d"
echo -e "\n"

echo "logout:"
LOGOUT_JSON=$(curl -sS -X POST http://127.0.0.1:8001/api/v1/auth/logout \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}")
echo "$LOGOUT_JSON"
printf '%s' "$LOGOUT_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('success') is True, d"
echo -e "\n"

echo "me_after_logout:"
ME_AFTER_LOGOUT_JSON=$(curl -sS http://127.0.0.1:8001/api/v1/me -H "Authorization: Bearer $ACCESS_TOKEN")
echo "$ME_AFTER_LOGOUT_JSON"
printf '%s' "$ME_AFTER_LOGOUT_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('code')=='http_error' and 'Session is not active' in d.get('message',''), d"
echo -e "\n"

echo "validation_sample:"
VALIDATION_JSON=$(curl -sS -X POST http://127.0.0.1:8001/api/v1/auth/start \
  -H "Content-Type: application/json" \
  -d '{"device_id":"missing-login"}')
echo "$VALIDATION_JSON"
printf '%s' "$VALIDATION_JSON" | python -c "import json,sys; d=json.load(sys.stdin); assert d.get('code')=='validation_error', d"
echo -e "\n"

echo "smoke_done: OK"
