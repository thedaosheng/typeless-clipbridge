#!/usr/bin/env bash
set -uo pipefail

APP_NAME="TypelessClipbridge"
INTERVAL="${TCB_INTERVAL:-1}"
PEERS_CSV="${TCB_PEERS:-${PEER:-}}"
LOG_PREFIX_LEN="${TCB_LOG_PREFIX_LEN:-0}"
SSH_BIN="${TCB_SSH:-/usr/bin/ssh}"

export LANG="${LANG:-en_US.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-en_US.UTF-8}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  STATE_DIR="${TCB_STATE_DIR:-$HOME/Library/Application Support/${APP_NAME}}"
else
  STATE_DIR="${TCB_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/typeless-clipbridge}"
fi

LOG_FILE="${TCB_LOG_FILE:-$STATE_DIR/clip-sync.log}"
MIRROR_FILE="$STATE_DIR/clipboard.txt"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true

PEERS=()
if [[ -n "$PEERS_CSV" ]]; then
  IFS=',' read -r -a PEERS <<< "$PEERS_CSV"
fi

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG_FILE"
}

setup_linux_gui_env() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    return 0
  fi

  if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "/run/user/$(id -u)" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  fi
  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "${XDG_RUNTIME_DIR:-}/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi
  if [[ -z "${WAYLAND_DISPLAY:-}" && -S "${XDG_RUNTIME_DIR:-}/wayland-0" ]]; then
    export WAYLAND_DISPLAY="wayland-0"
  fi
  if [[ -z "${DISPLAY:-}" && -S /tmp/.X11-unix/X0 ]]; then
    export DISPLAY=":0"
  fi
  if [[ -z "${XAUTHORITY:-}" && -f "$HOME/.Xauthority" ]]; then
    export XAUTHORITY="$HOME/.Xauthority"
  fi
}

clipboard_provider() {
  setup_linux_gui_env

  case "$(uname -s)" in
    Darwin)
      if command -v pbpaste >/dev/null 2>&1 && command -v pbcopy >/dev/null 2>&1; then
        printf 'macos'
        return 0
      fi
      ;;
    Linux)
      if command -v wl-paste >/dev/null 2>&1 && command -v wl-copy >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        printf 'wayland'
        return 0
      fi
      if command -v xclip >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
        printf 'xclip'
        return 0
      fi
      if command -v xsel >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
        printf 'xsel'
        return 0
      fi
      ;;
  esac

  printf 'file'
}

read_clipboard_to_file() {
  local provider="$1"
  local output="$2"

  case "$provider" in
    macos)
      pbpaste > "$output" 2>/dev/null || : > "$output"
      ;;
    wayland)
      wl-paste --no-newline > "$output" 2>/dev/null || : > "$output"
      ;;
    xclip)
      xclip -selection clipboard -out > "$output" 2>/dev/null || : > "$output"
      ;;
    xsel)
      xsel --clipboard --output > "$output" 2>/dev/null || : > "$output"
      ;;
    *)
      if [[ -f "$MIRROR_FILE" ]]; then
        cat "$MIRROR_FILE" > "$output"
      else
        : > "$output"
      fi
      ;;
  esac
}

write_file_to_clipboard() {
  local provider="$1"
  local input="$2"

  case "$provider" in
    macos)
      pbcopy < "$input"
      ;;
    wayland)
      wl-copy < "$input"
      ;;
    xclip)
      xclip -selection clipboard -in < "$input"
      ;;
    xsel)
      xsel --clipboard --input < "$input"
      ;;
    *)
      cp "$input" "$MIRROR_FILE"
      chmod 600 "$MIRROR_FILE" 2>/dev/null || true
      ;;
  esac
}

mirror_file() {
  local input="$1"
  cp "$input" "$MIRROR_FILE"
  chmod 600 "$MIRROR_FILE" 2>/dev/null || true
}

hash_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    cksum "$file" | awk '{print $1 ":" $2}'
  fi
}

file_size() {
  wc -c < "$1" | tr -d ' '
}

preview_file() {
  local file="$1"
  if [[ "$LOG_PREFIX_LEN" == "0" ]]; then
    return 0
  fi
  LC_ALL=C head -c "$LOG_PREFIX_LEN" "$file" | tr '\n' ' '
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

remote_clipboard_to_file() {
  local peer="$1"
  local output="$2"
  local remote_script quoted

  remote_script='export LANG=${LANG:-en_US.UTF-8}; export LC_CTYPE=${LC_CTYPE:-en_US.UTF-8}; mac="$HOME/Library/Application Support/TypelessClipbridge/clipboard.txt"; linux="${XDG_STATE_HOME:-$HOME/.local/state}/typeless-clipbridge/clipboard.txt"; if [ -r "$mac" ]; then cat "$mac"; elif [ -r "$linux" ]; then cat "$linux"; elif command -v pbpaste >/dev/null 2>&1; then pbpaste; elif command -v wl-paste >/dev/null 2>&1; then wl-paste --no-newline; elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard -out; elif command -v xsel >/dev/null 2>&1; then xsel --clipboard --output; fi'
  quoted="$(shell_quote "$remote_script")"

  "$SSH_BIN" \
    -o ConnectTimeout="${TCB_SSH_TIMEOUT:-3}" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    "$peer" "sh -lc $quoted" > "$output" 2>/dev/null
}

compact_peers() {
  local peer
  local compact=()
  if [[ -z "$PEERS_CSV" ]]; then
    PEERS=()
    return 0
  fi
  for peer in "${PEERS[@]}"; do
    peer="${peer#"${peer%%[![:space:]]*}"}"
    peer="${peer%"${peer##*[![:space:]]}"}"
    if [[ -n "$peer" ]]; then
      compact+=("$peer")
    fi
  done
  PEERS=("${compact[@]}")
}

compact_peers

if [[ "${1:-}" == "--once" ]]; then
  INTERVAL=0
fi

if [[ -z "$PEERS_CSV" ]]; then
  log "no peers configured; set TCB_PEERS=user@tailscale-ip[,user@tailscale-ip]"
fi

log "started peers=${PEERS_CSV:-none} interval=${INTERVAL}s"

last_local_hash=""
peer_hashes=()
seeded=0

while true; do
  provider="$(clipboard_provider)"
  local_tmp="$(mktemp "${TMPDIR:-/tmp}/tcb-local.XXXXXX")" || exit 1
  read_clipboard_to_file "$provider" "$local_tmp"
  local_hash="$(hash_file "$local_tmp")"

  if [[ "$local_hash" != "$last_local_hash" ]]; then
    mirror_file "$local_tmp"
    bytes="$(file_size "$local_tmp")"
    log "local mirror provider=${provider} bytes=${bytes}"
    last_local_hash="$local_hash"
  fi

  if [[ -n "$PEERS_CSV" ]]; then
    for idx in "${!PEERS[@]}"; do
      peer="${PEERS[$idx]}"
      remote_tmp="$(mktemp "${TMPDIR:-/tmp}/tcb-remote.XXXXXX")" || exit 1

      if remote_clipboard_to_file "$peer" "$remote_tmp"; then
        remote_hash="$(hash_file "$remote_tmp")"
        bytes="$(file_size "$remote_tmp")"

        if [[ "$seeded" == "0" ]]; then
          peer_hashes[$idx]="$remote_hash"
        elif [[ "$bytes" != "0" && "${peer_hashes[$idx]:-}" != "$remote_hash" ]]; then
          peer_hashes[$idx]="$remote_hash"
          if [[ "$remote_hash" != "$local_hash" ]]; then
            if write_file_to_clipboard "$provider" "$remote_tmp"; then
              mirror_file "$remote_tmp"
              local_hash="$remote_hash"
              last_local_hash="$remote_hash"
              log "pulled peer=${peer} bytes=${bytes} preview=$(preview_file "$remote_tmp")"
            else
              log "copy failed peer=${peer}"
            fi
          fi
        fi
      else
        log "peer unreachable peer=${peer}"
      fi

      rm -f "$remote_tmp"
    done
  fi

  rm -f "$local_tmp"
  seeded=1

  if [[ "$INTERVAL" == "0" ]]; then
    exit 0
  fi
  sleep "$INTERVAL"
done
