#!/bin/sh
set -eu

DEFAULT_BASE_URLS='https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main
https://fastly.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main
https://gcore.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main
https://raw.githubusercontent.com/thedaosheng/typeless-clipbridge/main'
TMP_DIR="${TMPDIR:-/tmp}"
TMP_FILE="${TMP_DIR}/typeless-clipbridge-install.$$"

cleanup() {
  rm -f "$TMP_FILE"
}
trap cleanup EXIT INT TERM

if [ -n "${TCB_DEV_ROOT:-}" ] && [ -f "${TCB_DEV_ROOT}/install.sh" ]; then
  exec bash "${TCB_DEV_ROOT}/install.sh" "$@"
fi

if [ -n "${TCB_BASE_URL:-}" ]; then
  BASE_URLS="$TCB_BASE_URL"
elif [ -n "${TCB_BASE_URLS:-}" ]; then
  BASE_URLS="$TCB_BASE_URLS"
else
  BASE_URLS="$DEFAULT_BASE_URLS"
fi

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "typeless-clipbridge: curl or wget is required." >&2
  exit 1
fi

for base in $BASE_URLS; do
  base="${base%/}"
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --connect-timeout 8 --retry 1 "${base}/install.sh" -o "$TMP_FILE" 2>/dev/null; then
      export TCB_BASE_URL="$base"
      break
    fi
  elif wget -q --timeout=8 -O "$TMP_FILE" "${base}/install.sh" 2>/dev/null; then
    export TCB_BASE_URL="$base"
    break
  fi
done

if [ ! -s "$TMP_FILE" ]; then
  echo "typeless-clipbridge: failed to download install.sh from all mirrors." >&2
  exit 1
fi

if command -v bash >/dev/null 2>&1; then
  exec bash "$TMP_FILE" "$@"
fi

echo "typeless-clipbridge: bash is required." >&2
exit 1
