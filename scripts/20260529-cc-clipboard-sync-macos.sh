#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "clipboard-sync template currently supports macOS only." >&2
  exit 1
fi

: "${PEER_USER:?Set PEER_USER to the remote macOS account name}"
: "${PEER_HOST:?Set PEER_HOST to the remote macOS host or IP}"

PEER_KEY="${PEER_KEY:-${HOME}/.ssh/id_ed25519}"
POLL_INTERVAL="${POLL_INTERVAL:-1}"
SSH_TIMEOUT="${SSH_TIMEOUT:-2}"
LOG_PREFIX_LEN="${LOG_PREFIX_LEN:-30}"

export LANG="${LANG:-en_US.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-en_US.UTF-8}"

SSH_OPTS=(
  -o "ConnectTimeout=${SSH_TIMEOUT}"
  -o "BatchMode=yes"
  -o "StrictHostKeyChecking=no"
  -i "${PEER_KEY}"
)
REMOTE_ENV="LANG=en_US.UTF-8 LC_CTYPE=en_US.UTF-8"

last_content=""

log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[${ts}] $*"
}

log "started clipboard sync, peer=${PEER_USER}@${PEER_HOST}, interval=${POLL_INTERVAL}s"

while true; do
  current_content="$(ssh "${SSH_OPTS[@]}" "${PEER_USER}@${PEER_HOST}" "${REMOTE_ENV} /usr/bin/pbpaste" 2>/dev/null || true)"

  if [[ -n "${current_content}" && "${current_content}" != "${last_content}" ]]; then
    printf '%s' "${current_content}" | /usr/bin/pbcopy
    preview="$(printf '%s' "${current_content}" | head -c "${LOG_PREFIX_LEN}" | tr '\n' ' ')"
    log "synced clipboard: ${preview}..."
    last_content="${current_content}"
  fi

  sleep "${POLL_INTERVAL}"
done
