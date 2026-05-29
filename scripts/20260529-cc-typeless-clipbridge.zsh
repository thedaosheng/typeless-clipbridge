#!/bin/zsh
set -u

DB_PATH="${TYPELESS_DB_PATH:-$HOME/Library/Application Support/Typeless/typeless.db}"
STATE_DIR="${TYPELESS_CLIPBRIDGE_STATE_DIR:-$HOME/Library/Application Support/TypelessClipbridge}"
STATE_FILE="$STATE_DIR/last-key"
LOG_FILE="$STATE_DIR/watcher.log"
POLL_INTERVAL="${TYPELESS_CLIPBRIDGE_INTERVAL:-1}"

export LANG="${LANG:-en_US.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-en_US.UTF-8}"

SQLITE="${TYPELESS_SQLITE:-/usr/bin/sqlite3}"
PBCOPY="${TYPELESS_PBCOPY:-/usr/bin/pbcopy}"
PBPASTE="${TYPELESS_PBPASTE:-/usr/bin/pbpaste}"
XXD="${TYPELESS_XXD:-/usr/bin/xxd}"
SSH="${TYPELESS_SSH:-/usr/bin/ssh}"
COPY_DELAYS="${TYPELESS_CLIPBRIDGE_DELAYS:-0.8 2 4 8 15}"

REMOTE_CLIPBOARD_ENABLED="${TYPELESS_REMOTE_CLIPBOARD_ENABLED:-0}"
REMOTE_CLIPBOARD_USER="${TYPELESS_REMOTE_CLIPBOARD_USER:-}"
REMOTE_CLIPBOARD_HOST="${TYPELESS_REMOTE_CLIPBOARD_HOST:-}"
REMOTE_CLIPBOARD_KEY="${TYPELESS_REMOTE_CLIPBOARD_KEY:-$HOME/.ssh/id_ed25519}"

mkdir -p "$STATE_DIR"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG_FILE"
}

latest_query() {
  "$SQLITE" -readonly -batch -noheader "$DB_PATH" "
    SELECT source || '|' || id || '|' || ts || char(9) || hex(refined_text)
    FROM (
      SELECT
        'history_v2' AS source,
        id,
        refined_text,
        COALESCE(updated_at, created_at, '') AS ts
      FROM history_v2
      WHERE refined_text IS NOT NULL
        AND length(trim(refined_text)) > 0
        AND status IN ('completed', 'transcript')
      UNION ALL
      SELECT
        'history' AS source,
        id,
        refined_text,
        COALESCE(updated_at, created_at, '') AS ts
      FROM history
      WHERE refined_text IS NOT NULL
        AND length(trim(refined_text)) > 0
        AND status IN ('completed', 'transcript')
    )
    ORDER BY ts DESC
    LIMIT 1;
  " 2>/dev/null | head -n 1
}

with_decoded_text_file() {
  local hex="$1"
  local callback="$2"
  local tmp

  tmp="$(mktemp "${TMPDIR:-/tmp}/typeless-clipbridge.XXXXXX")" || return 1
  printf '%s' "$hex" | "$XXD" -r -p > "$tmp"
  "$callback" "$tmp"
  local exit_code=$?
  rm -f "$tmp"
  return $exit_code
}

copy_text_file_to_remote_clipboard() {
  if [[ "$REMOTE_CLIPBOARD_ENABLED" != "1" ]]; then
    return 0
  fi

  if [[ -z "$REMOTE_CLIPBOARD_USER" || -z "$REMOTE_CLIPBOARD_HOST" ]]; then
    log "remote clipboard enabled but user/host missing"
    return 0
  fi

  [[ -x "$SSH" && -f "$REMOTE_CLIPBOARD_KEY" ]] || return 0

  "$SSH" \
    -o ConnectTimeout=2 \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -i "$REMOTE_CLIPBOARD_KEY" \
    "${REMOTE_CLIPBOARD_USER}@${REMOTE_CLIPBOARD_HOST}" \
    "LANG=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 /usr/bin/pbcopy" < "$1" >/dev/null 2>&1
}

copy_text_file_to_clipboard() {
  "$PBCOPY" < "$1"
  local local_exit=$?
  copy_text_file_to_remote_clipboard "$1" || true
  return $local_exit
}

verify_text_file_on_clipboard() {
  local tmp_clip

  tmp_clip="$(mktemp "${TMPDIR:-/tmp}/typeless-clipbridge-current.XXXXXX")" || return 1
  "$PBPASTE" > "$tmp_clip"
  cmp -s "$1" "$tmp_clip"
  local exit_code=$?
  rm -f "$tmp_clip"
  return $exit_code
}

copy_hex_to_clipboard() {
  with_decoded_text_file "$1" copy_text_file_to_clipboard
}

verify_hex_on_clipboard() {
  with_decoded_text_file "$1" verify_text_file_on_clipboard
}

copy_hex_after_delays() {
  local key="$1"
  local hex="$2"
  local delay

  for delay in ${(z)COPY_DELAYS}; do
    sleep "$delay"

    if [[ -f "$STATE_FILE" && "$(<"$STATE_FILE")" != "$key" ]]; then
      log "skip stale delayed copy $key"
      return 0
    fi

    if verify_hex_on_clipboard "$hex"; then
      log "already verified $key delay=${delay}s"
    elif copy_hex_to_clipboard "$hex"; then
      if verify_hex_on_clipboard "$hex"; then
        log "copied verified $key delay=${delay}s"
      else
        log "copied unverified $key delay=${delay}s"
      fi
    else
      log "copy failed $key delay=${delay}s"
    fi
  done
}

print_latest() {
  local row key hex
  row="$(latest_query || true)"
  if [[ -z "$row" ]]; then
    return 1
  fi

  key="${row%%	*}"
  hex="${row#*	}"
  printf 'key=%s\ntext=\n' "$key"
  printf '%s' "$hex" | "$XXD" -r -p
  printf '\n'
}

if [[ "${1:-}" == "--print-latest" ]]; then
  print_latest
  exit $?
fi

if [[ ! -x "$SQLITE" || ! -x "$PBCOPY" || ! -x "$PBPASTE" || ! -x "$XXD" ]]; then
  log "missing required system tools"
  exit 1
fi

initialized=0
last_key=""

if [[ -f "$STATE_FILE" ]]; then
  last_key="$(<"$STATE_FILE")"
  initialized=1
fi

log "started"

while true; do
  if [[ ! -f "$DB_PATH" ]]; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  row="$(latest_query || true)"
  if [[ -n "$row" ]]; then
    key="${row%%	*}"
    hex="${row#*	}"

    if [[ "$key" != "$row" && -n "$hex" ]]; then
      if (( initialized == 0 )); then
        last_key="$key"
        printf '%s' "$last_key" > "$STATE_FILE"
        initialized=1
        log "seeded $key"
      elif [[ "$key" != "$last_key" ]]; then
        last_key="$key"
        printf '%s' "$last_key" > "$STATE_FILE"
        log "queued $key"
        copy_hex_after_delays "$key" "$hex" &
      fi
    fi
  fi

  sleep "$POLL_INTERVAL"
done
