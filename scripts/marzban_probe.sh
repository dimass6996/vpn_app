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
MARZBAN_PROBE_USERNAME="${MARZBAN_PROBE_USERNAME:-manual-user}"

if [[ -z "$MARZBAN_BASE_URL" || -z "$MARZBAN_SUDO_USERNAME" || -z "$MARZBAN_SUDO_PASSWORD" ]]; then
  echo "probe_error: MARZBAN_BASE_URL/MARZBAN_SUDO_USERNAME/MARZBAN_SUDO_PASSWORD must be set"
  exit 1
fi

for cmd in curl python; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "probe_error: missing required command '$cmd'"
    exit 1
  fi
done

TOKEN_BODY_FILE="/tmp/arbuz_marzban_probe_token.json"
USER_BODY_FILE="/tmp/arbuz_marzban_probe_user.json"

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
  echo "probe_error: failed to obtain Marzban admin token"
  exit 1
fi

ACCESS_TOKEN=$(python -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8')).get('access_token',''))" "$TOKEN_BODY_FILE")
if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "probe_error: Marzban token response does not contain access_token"
  exit 1
fi

USER_STATUS=$(curl -sS -o "$USER_BODY_FILE" -w "%{http_code}" \
  -X GET "$MARZBAN_BASE_URL/api/user/$MARZBAN_PROBE_USERNAME" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  --connect-timeout 8 \
  --max-time 20)

echo "probe_base_url: $MARZBAN_BASE_URL"
echo "probe_username: $MARZBAN_PROBE_USERNAME"
echo "probe_user_status: $USER_STATUS"
echo

if [[ "$USER_STATUS" == "404" ]]; then
  echo "probe_result: user_not_found"
  exit 0
fi

if [[ "$USER_STATUS" -lt 200 || "$USER_STATUS" -ge 300 ]]; then
  echo "probe_user_response:"
  cat "$USER_BODY_FILE" || true
  echo
  USERS_STATUS=$(curl -sS -o /tmp/arbuz_marzban_probe_users.json -w "%{http_code}" \
    -X GET "$MARZBAN_BASE_URL/api/users" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    --connect-timeout 8 \
    --max-time 20 || true)
  echo "probe_users_status: $USERS_STATUS"
  echo "probe_users_response:"
  cat /tmp/arbuz_marzban_probe_users.json || true
  echo
  echo "probe_error: failed to read user from Marzban"
  exit 1
fi

python - "$USER_BODY_FILE" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
summary = {
    "username": payload.get("username"),
    "status": payload.get("status"),
    "expire": payload.get("expire"),
    "subscription_url": payload.get("subscription_url"),
}
print("probe_user_summary:")
print(json.dumps(summary, ensure_ascii=True, indent=2))
PY

echo "probe_done: OK"
