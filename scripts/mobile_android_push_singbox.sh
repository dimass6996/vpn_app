#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_BINARY="$PROJECT_ROOT/mobile/app/android/sing-box"
SINGBOX_BINARY_PATH="${SINGBOX_BINARY_PATH:-$DEFAULT_BINARY}"
ANDROID_SERIAL="${ANDROID_SERIAL:-}"

if [[ ! -f "$SINGBOX_BINARY_PATH" ]]; then
  echo "push_error: sing-box binary not found at $SINGBOX_BINARY_PATH"
  echo "hint: set SINGBOX_BINARY_PATH=/abs/path/to/sing-box-android"
  exit 1
fi

ADB_ARGS=()
if [[ -n "$ANDROID_SERIAL" ]]; then
  ADB_ARGS+=("-s" "$ANDROID_SERIAL")
fi

echo "push_binary: $SINGBOX_BINARY_PATH"
adb "${ADB_ARGS[@]}" push "$SINGBOX_BINARY_PATH" /data/local/tmp/sing-box >/dev/null
adb "${ADB_ARGS[@]}" shell chmod 755 /data/local/tmp/sing-box

echo "push_done: /data/local/tmp/sing-box"
