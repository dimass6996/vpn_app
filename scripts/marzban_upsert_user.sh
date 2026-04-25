#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$PROJECT_ROOT/infra/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/infra/.env"
  set +a
fi

MARZBAN_BASE_URL="${MARZBAN_BASE_URL:-}"
MARZBAN_SUDO_USERNAME="${MARZBAN_SUDO_USERNAME:-}"
MARZBAN_SUDO_PASSWORD="${MARZBAN_SUDO_PASSWORD:-}"
MARZBAN_TARGET_USERNAME="${MARZBAN_TARGET_USERNAME:-manual-user}"
MARZBAN_TARGET_DAYS="${MARZBAN_TARGET_DAYS:-30}"

if [[ -z "$MARZBAN_BASE_URL" || -z "$MARZBAN_SUDO_USERNAME" || -z "$MARZBAN_SUDO_PASSWORD" ]]; then
  echo "upsert_error: MARZBAN_BASE_URL/MARZBAN_SUDO_USERNAME/MARZBAN_SUDO_PASSWORD must be set"
  exit 1
fi

for cmd in curl python; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "upsert_error: missing required command '$cmd'"
    exit 1
  fi
done

TOKEN_BODY_FILE="/tmp/arbuz_marzban_upsert_token.json"
USER_BODY_FILE="/tmp/arbuz_marzban_upsert_user.json"
UPSERT_BODY_FILE="/tmp/arbuz_marzban_upsert_result.json"

TOKEN_STATUS=$(curl -sS -o "$TOKEN_BODY_FILE" -w "%{http_code}" \
  -X POST "$MARZBAN_BASE_URL/api/admin/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --connect-timeout 8 \
  --max-time 20 \
  -d "username=$MARZBAN_SUDO_USERNAME&password=$MARZBAN_SUDO_PASSWORD")

if [[ "$TOKEN_STATUS" -lt 200 || "$TOKEN_STATUS" -ge 300 ]]; then
  echo "token_status: $TOKEN_STATUS"
  echo "token_response:"
  cat "$TOKEN_BODY_FILE" || true
  echo
  echo "upsert_error: failed to obtain Marzban admin token"
  exit 1
fi

ACCESS_TOKEN=$(python -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8')).get('access_token',''))" "$TOKEN_BODY_FILE")
if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "upsert_error: Marzban token response does not contain access_token"
  exit 1
fi

EXPIRE_TS=$(python - "$MARZBAN_TARGET_DAYS" <<'PY'
import sys
import time

days = int(sys.argv[1])
print(int(time.time()) + max(days, 0) * 86400)
PY
)

PAYLOAD="{\"username\":\"$MARZBAN_TARGET_USERNAME\",\"status\":\"active\",\"expire\":$EXPIRE_TS}"

USER_STATUS=$(curl -sS -o "$USER_BODY_FILE" -w "%{http_code}" \
  -X GET "$MARZBAN_BASE_URL/api/user/$MARZBAN_TARGET_USERNAME" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --connect-timeout 8 \
  --max-time 20)

if [[ "$USER_STATUS" == "404" ]]; then
  ACTION="created"
  UPSERT_STATUS=$(curl -sS -o "$UPSERT_BODY_FILE" -w "%{http_code}" \
    -X POST "$MARZBAN_BASE_URL/api/user" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --connect-timeout 8 \
    --max-time 20 \
    -d "$PAYLOAD")
else
  ACTION="updated"
  UPSERT_STATUS=$(curl -sS -o "$UPSERT_BODY_FILE" -w "%{http_code}" \
    -X PUT "$MARZBAN_BASE_URL/api/user/$MARZBAN_TARGET_USERNAME" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    --connect-timeout 8 \
    --max-time 20 \
    -d "{\"status\":\"active\",\"expire\":$EXPIRE_TS}")
fi

echo "upsert_base_url: $MARZBAN_BASE_URL"
echo "upsert_username: $MARZBAN_TARGET_USERNAME"
echo "upsert_action: $ACTION"
echo "upsert_status: $UPSERT_STATUS"
echo

if [[ "$UPSERT_STATUS" -lt 200 || "$UPSERT_STATUS" -ge 300 ]]; then
  echo "upsert_response:"
  cat "$UPSERT_BODY_FILE" || true
  echo
  USERS_STATUS=$(curl -sS -o /tmp/arbuz_marzban_upsert_users.json -w "%{http_code}" \
    -X GET "$MARZBAN_BASE_URL/api/users" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    --connect-timeout 8 \
    --max-time 20 || true)
  echo "upsert_users_status: $USERS_STATUS"
  echo "upsert_users_response:"
  cat /tmp/arbuz_marzban_upsert_users.json || true
  echo
  echo "upsert_error: Marzban upsert request failed"
  exit 1
fi

python - "$UPSERT_BODY_FILE" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
summary = {
    "username": payload.get("username"),
    "status": payload.get("status"),
    "expire": payload.get("expire"),
    "subscription_url": payload.get("subscription_url"),
}
print("upsert_user_summary:")
print(json.dumps(summary, ensure_ascii=True, indent=2))
PY

echo "upsert_done: OK"
