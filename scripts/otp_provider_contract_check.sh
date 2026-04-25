#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$PROJECT_ROOT/infra/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/infra/.env"
  set +a
fi

AUTH_HTTP_OTP_URL="${AUTH_HTTP_OTP_URL:-}"
AUTH_HTTP_OTP_TOKEN="${AUTH_HTTP_OTP_TOKEN:-}"
OTP_CHECK_LOGIN="${OTP_CHECK_LOGIN:-otp-contract-check}"
OTP_CHECK_CODE="${OTP_CHECK_CODE:-123456}"
OTP_CHECK_DEVICE_ID="${OTP_CHECK_DEVICE_ID:-contract-check-device}"

if [[ -z "$AUTH_HTTP_OTP_URL" ]]; then
  echo "contract_error: AUTH_HTTP_OTP_URL is empty"
  exit 1
fi

unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY ftp_proxy FTP_PROXY
export NO_PROXY="127.0.0.1,localhost"
export no_proxy="127.0.0.1,localhost"

BODY_FILE="/tmp/arbuz_otp_contract_body.json"
REQUEST_BODY="{\"login\":\"$OTP_CHECK_LOGIN\",\"code\":\"$OTP_CHECK_CODE\",\"device_id\":\"$OTP_CHECK_DEVICE_ID\"}"

if [[ -n "$AUTH_HTTP_OTP_TOKEN" ]]; then
  STATUS_CODE=$(curl -sS -o "$BODY_FILE" -w "%{http_code}" \
    -X POST "$AUTH_HTTP_OTP_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_HTTP_OTP_TOKEN" \
    --connect-timeout 5 \
    --max-time 15 \
    -d "$REQUEST_BODY")
else
  STATUS_CODE=$(curl -sS -o "$BODY_FILE" -w "%{http_code}" \
    -X POST "$AUTH_HTTP_OTP_URL" \
    -H "Content-Type: application/json" \
    --connect-timeout 5 \
    --max-time 15 \
    -d "$REQUEST_BODY")
fi

echo "contract_request:"
echo "$REQUEST_BODY"
echo
echo "contract_response_status:"
echo "$STATUS_CODE"
echo
echo "contract_response_body:"
cat "$BODY_FILE" || true
echo

if [[ "$STATUS_CODE" -lt 200 || "$STATUS_CODE" -ge 300 ]]; then
  echo "contract_error: OTP provider did not return 2xx"
  exit 1
fi

echo "contract_check_done: OK"
