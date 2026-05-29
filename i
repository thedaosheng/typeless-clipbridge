#!/bin/sh
set -eu

BASE_URL="${TCB_BASE_URL:-https://raw.githubusercontent.com/thedaosheng/typeless-clipbridge/main}"
TMP_DIR="${TMPDIR:-/tmp}"
TMP_FILE="${TMP_DIR}/typeless-clipbridge-install.$$"

cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT INT TERM

if [ -n "${TCB_DEV_ROOT:-}" ] && [ -f "${TCB_DEV_ROOT}/install.sh" ]; then
  exec bash "${TCB_DEV_ROOT}/install.sh" "$@"
fi

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${BASE_URL}/install.sh" -o "$TMP_FILE"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP_FILE" "${BASE_URL}/install.sh"
else
  echo "typeless-clipbridge: curl or wget is required." >&2
  exit 1
fi

if command -v bash >/dev/null 2>&1; then
  exec bash "$TMP_FILE" "$@"
fi

echo "typeless-clipbridge: bash is required." >&2
exit 1
