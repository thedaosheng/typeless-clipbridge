#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TypelessClipbridge"
VERSION="2026.05.29"
DEFAULT_BASE_URLS=$'https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main\nhttps://fastly.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main\nhttps://gcore.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main\nhttps://raw.githubusercontent.com/thedaosheng/typeless-clipbridge/main'
PREFIX="${TCB_PREFIX:-$HOME/.typeless-clipbridge}"
BIN_DIR="$PREFIX/bin"
PEERS_CSV="${TCB_PEERS:-}"
POLL_INTERVAL="${TCB_INTERVAL:-1}"
COPY_DELAYS="${TYPELESS_CLIPBRIDGE_DELAYS:-0.8 2 4 8 15}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
INSTALL_TAILSCALE=1
INSTALL_DEPS=1
INSTALL_SYNC="auto"
INSTALL_TYPELESS="auto"
DRY_RUN=0
YES=0
ACTION="install"

if [[ -n "${TCB_BASE_URL:-}" ]]; then
  BASE_URLS="$TCB_BASE_URL"
elif [[ -n "${TCB_BASE_URLS:-}" ]]; then
  BASE_URLS="$TCB_BASE_URLS"
else
  BASE_URLS="$DEFAULT_BASE_URLS"
fi

first_base_url() {
  local base
  for base in $BASE_URLS; do
    printf '%s\n' "${base%/}"
    return 0
  done
}

ACTIVE_BASE_URL="$(first_base_url)"

case "$(uname -s)" in
  Darwin)
    OS="macos"
    STATE_DIR="${TCB_STATE_DIR:-$HOME/Library/Application Support/${APP_NAME}}"
    ;;
  Linux)
    OS="linux"
    STATE_DIR="${TCB_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/typeless-clipbridge}"
    ;;
  *)
    OS="unsupported"
    STATE_DIR="${TCB_STATE_DIR:-$HOME/.typeless-clipbridge/state}"
    ;;
esac

usage() {
  cat <<'USAGE'
Typeless Clipbridge one-line installer.

Quick start:
  curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh
  curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh -s -- --peer user@100.x.x.x

Options:
  --peer user@host              Add a clipboard peer over SSH. Repeatable.
  --peers a@host,b@host         Add multiple peers.
  --typeless                    Force-install the Typeless SQLite watcher on macOS.
  --no-typeless                 Do not install the Typeless watcher.
  --sync                        Force-install clipboard sync. Requires peers.
  --no-sync                     Do not install clipboard sync.
  --install-tailscale           Install Tailscale if missing. Default.
  --no-tailscale                Do not install or start Tailscale.
  --tailscale-authkey KEY       Use an auth key to join the tailnet when possible.
  --no-deps                     Do not try to install missing Linux clipboard tools.
  --interval SECONDS            Clipboard polling interval. Default: 1.
  --dry-run                     Print actions without writing files or services.
  --status                      Show installed status.
  --uninstall                   Remove installed services.
  -y, --yes                     Non-interactive defaults.
  -h, --help                    Show this help.
USAGE
}

log() {
  printf '[typeless-clipbridge] %s\n' "$*"
}

warn() {
  printf '[typeless-clipbridge] warning: %s\n' "$*" >&2
}

fail() {
  printf '[typeless-clipbridge] error: %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[typeless-clipbridge] dry-run:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

append_peer() {
  local peer="$1"
  if [[ -z "$peer" ]]; then
    return 0
  fi
  if [[ -z "$PEERS_CSV" ]]; then
    PEERS_CSV="$peer"
  else
    PEERS_CSV="${PEERS_CSV},${peer}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --peer)
      [[ $# -ge 2 ]] || fail "--peer requires user@host"
      append_peer "$2"
      shift 2
      ;;
    --peer=*)
      append_peer "${1#*=}"
      shift
      ;;
    --peers)
      [[ $# -ge 2 ]] || fail "--peers requires a comma-separated value"
      append_peer "$2"
      shift 2
      ;;
    --peers=*)
      append_peer "${1#*=}"
      shift
      ;;
    --typeless)
      INSTALL_TYPELESS=1
      shift
      ;;
    --no-typeless)
      INSTALL_TYPELESS=0
      shift
      ;;
    --sync)
      INSTALL_SYNC=1
      shift
      ;;
    --no-sync)
      INSTALL_SYNC=0
      shift
      ;;
    --install-tailscale)
      INSTALL_TAILSCALE=1
      shift
      ;;
    --no-tailscale)
      INSTALL_TAILSCALE=0
      shift
      ;;
    --tailscale-authkey|--authkey)
      [[ $# -ge 2 ]] || fail "$1 requires a key"
      TAILSCALE_AUTHKEY="$2"
      shift 2
      ;;
    --tailscale-authkey=*|--authkey=*)
      TAILSCALE_AUTHKEY="${1#*=}"
      shift
      ;;
    --no-deps)
      INSTALL_DEPS=0
      shift
      ;;
    --interval)
      [[ $# -ge 2 ]] || fail "--interval requires seconds"
      POLL_INTERVAL="$2"
      shift 2
      ;;
    --interval=*)
      POLL_INTERVAL="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --status)
      ACTION=status
      shift
      ;;
    --uninstall)
      ACTION=uninstall
      shift
      ;;
    -y|--yes)
      YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

find_tailscale() {
  if command -v tailscale >/dev/null 2>&1; then
    command -v tailscale
    return 0
  fi
  if [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
    printf '/Applications/Tailscale.app/Contents/MacOS/Tailscale\n'
    return 0
  fi
  return 1
}

download_asset() {
  local remote="$1"
  local dest="$2"
  local base url

  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run: download ${ACTIVE_BASE_URL}/${remote} -> ${dest}"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  if [[ -n "${TCB_DEV_ROOT:-}" && -f "${TCB_DEV_ROOT}/${remote}" ]]; then
    cp "${TCB_DEV_ROOT}/${remote}" "$dest"
  else
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
      fail "curl or wget is required"
    fi

    for base in $BASE_URLS; do
      base="${base%/}"
      url="${base}/${remote}"
      if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --connect-timeout 8 --retry 1 "$url" -o "$dest" 2>/dev/null; then
          ACTIVE_BASE_URL="$base"
          export TCB_BASE_URL="$base"
          break
        fi
      elif wget -q --timeout=8 -O "$dest" "$url" 2>/dev/null; then
        ACTIVE_BASE_URL="$base"
        export TCB_BASE_URL="$base"
        break
      fi
    done

    [[ -s "$dest" ]] || fail "failed to download ${remote} from all mirrors"
  fi
  chmod +x "$dest"
}

install_assets() {
  log "installing files into $PREFIX"
  run mkdir -p "$BIN_DIR" "$STATE_DIR"
  if [[ "$DRY_RUN" != "1" ]]; then
    chmod 700 "$STATE_DIR" 2>/dev/null || true
  fi
  download_asset "scripts/tcb" "$BIN_DIR/tcb"
  download_asset "scripts/tcb-clip-sync.sh" "$BIN_DIR/tcb-clip-sync.sh"
  download_asset "scripts/20260529-cc-typeless-clipbridge.zsh" "$BIN_DIR/typeless-watch.zsh"

  run mkdir -p "$HOME/.local/bin"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run: link $BIN_DIR/tcb -> $HOME/.local/bin/tcb"
  else
    ln -sf "$BIN_DIR/tcb" "$HOME/.local/bin/tcb"
  fi
}

install_tailscale_if_needed() {
  if [[ "$INSTALL_TAILSCALE" != "1" ]]; then
    return 0
  fi

  if ts="$(find_tailscale 2>/dev/null)"; then
    log "tailscale found: $ts"
  else
    case "$OS" in
      linux)
        log "installing Tailscale with the official Linux installer"
        if [[ "$DRY_RUN" == "1" ]]; then
          log "dry-run: curl -fsSL https://tailscale.com/install.sh | sh"
        else
          curl -fsSL https://tailscale.com/install.sh | sh
        fi
        ts="$(find_tailscale 2>/dev/null || true)"
        ;;
      macos)
        if command -v brew >/dev/null 2>&1; then
          log "installing Tailscale macOS app with Homebrew cask"
          run brew install --cask tailscale
          ts="$(find_tailscale 2>/dev/null || true)"
        else
          warn "Tailscale is missing. Install the Standalone macOS app from https://pkgs.tailscale.com/stable/#macos and rerun this installer."
          return 0
        fi
        ;;
    esac
  fi

  if [[ -z "${ts:-}" ]]; then
    return 0
  fi

  if "$ts" ip -4 >/dev/null 2>&1; then
    log "tailscale is connected: $("$ts" ip -4 2>/dev/null | tr '\n' ' ')"
    return 0
  fi

  if [[ -n "$TAILSCALE_AUTHKEY" ]]; then
    log "joining tailnet with auth key"
    if [[ "$OS" == "linux" ]]; then
      run sudo "$ts" up --authkey "$TAILSCALE_AUTHKEY" --ssh
    else
      run "$ts" up --authkey "$TAILSCALE_AUTHKEY"
    fi
  else
    if [[ "$OS" == "linux" ]]; then
      warn "Tailscale is installed but not connected. Run: sudo tailscale up --ssh"
    else
      warn "Tailscale is installed but not connected. Open Tailscale.app and sign in."
    fi
  fi
}

install_linux_clipboard_deps() {
  if [[ "$OS" != "linux" || "$INSTALL_DEPS" != "1" ]]; then
    return 0
  fi
  if command -v wl-copy >/dev/null 2>&1 || command -v xclip >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "installing Linux clipboard helpers with apt"
    run sudo apt-get update
    run sudo apt-get install -y wl-clipboard xclip xsel
  elif command -v dnf >/dev/null 2>&1; then
    log "installing Linux clipboard helpers with dnf"
    run sudo dnf install -y wl-clipboard xclip xsel
  elif command -v pacman >/dev/null 2>&1; then
    log "installing Linux clipboard helpers with pacman"
    run sudo pacman -S --needed --noconfirm wl-clipboard xclip xsel
  else
    warn "no supported package manager for clipboard helpers; file mirror fallback will still work"
  fi
}

prompt_for_peer_if_needed() {
  if [[ "$INSTALL_SYNC" == "0" || -n "$PEERS_CSV" || "$YES" == "1" ]]; then
    return 0
  fi
  if [[ -t 0 && -t 1 ]]; then
    printf 'Clipboard peer over SSH (user@tailscale-ip), empty to skip: '
    read -r peer || true
    append_peer "$peer"
  fi
}

should_install_sync() {
  if [[ "$INSTALL_SYNC" == "0" ]]; then
    return 1
  fi
  if [[ -n "$PEERS_CSV" ]]; then
    return 0
  fi
  if [[ "$INSTALL_SYNC" == "1" ]]; then
    fail "--sync requires --peer user@host"
  fi
  return 1
}

should_install_typeless() {
  if [[ "$OS" != "macos" ]]; then
    return 1
  fi
  if [[ "$INSTALL_TYPELESS" == "0" ]]; then
    return 1
  fi
  if [[ "$INSTALL_TYPELESS" == "1" ]]; then
    return 0
  fi
  [[ -f "$HOME/Library/Application Support/Typeless/typeless.db" || -d "/Applications/Typeless.app" ]]
}

install_macos_clip_sync() {
  local label="com.typelessclipbridge.clip-sync"
  local plist="$HOME/Library/LaunchAgents/${label}.plist"
  local uid

  uid="$(id -u)"
  log "installing macOS LaunchAgent ${label}"
  run mkdir -p "$HOME/Library/LaunchAgents" "$STATE_DIR"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run: write ${plist}"
  else
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml_escape "$BIN_DIR/tcb-clip-sync.sh")</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$STATE_DIR/clip-sync.stdout.log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$STATE_DIR/clip-sync.stderr.log")</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>LANG</key>
    <string>en_US.UTF-8</string>
    <key>LC_CTYPE</key>
    <string>en_US.UTF-8</string>
    <key>TCB_PEERS</key>
    <string>$(xml_escape "$PEERS_CSV")</string>
    <key>TCB_INTERVAL</key>
    <string>$(xml_escape "$POLL_INTERVAL")</string>
    <key>TCB_STATE_DIR</key>
    <string>$(xml_escape "$STATE_DIR")</string>
    <key>TCB_LOG_PREFIX_LEN</key>
    <string>${TCB_LOG_PREFIX_LEN:-0}</string>
  </dict>
</dict>
</plist>
PLIST
    plutil -lint "$plist"
    launchctl bootout "gui/${uid}" "$plist" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/${uid}" "$plist"
    launchctl enable "gui/${uid}/${label}"
    launchctl kickstart -k "gui/${uid}/${label}"
  fi
}

install_macos_typeless_watch() {
  local label="com.typelessclipbridge.typeless-watch"
  local plist="$HOME/Library/LaunchAgents/${label}.plist"
  local db_path="${TYPELESS_DB_PATH:-$HOME/Library/Application Support/Typeless/typeless.db}"
  local uid

  uid="$(id -u)"
  log "installing macOS LaunchAgent ${label}"
  run mkdir -p "$HOME/Library/LaunchAgents" "$STATE_DIR"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run: write ${plist}"
  else
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$(xml_escape "$BIN_DIR/typeless-watch.zsh")</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$STATE_DIR/typeless.stdout.log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$STATE_DIR/typeless.stderr.log")</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>LANG</key>
    <string>en_US.UTF-8</string>
    <key>LC_CTYPE</key>
    <string>en_US.UTF-8</string>
    <key>TYPELESS_DB_PATH</key>
    <string>$(xml_escape "$db_path")</string>
    <key>TYPELESS_CLIPBRIDGE_STATE_DIR</key>
    <string>$(xml_escape "$STATE_DIR")</string>
    <key>TYPELESS_CLIPBRIDGE_INTERVAL</key>
    <string>1</string>
    <key>TYPELESS_CLIPBRIDGE_DELAYS</key>
    <string>$(xml_escape "$COPY_DELAYS")</string>
    <key>TYPELESS_REMOTE_CLIPBOARD_ENABLED</key>
    <string>0</string>
  </dict>
</dict>
</plist>
PLIST
    plutil -lint "$plist"
    zsh -n "$BIN_DIR/typeless-watch.zsh"
    launchctl bootout "gui/${uid}" "$plist" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/${uid}" "$plist"
    launchctl enable "gui/${uid}/${label}"
    launchctl kickstart -k "gui/${uid}/${label}"
  fi
}

install_linux_clip_sync() {
  local service_dir="$HOME/.config/systemd/user"
  local service="${service_dir}/typeless-clipbridge-clip-sync.service"

  log "installing Linux systemd user service typeless-clipbridge-clip-sync.service"
  run mkdir -p "$service_dir" "$STATE_DIR"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "dry-run: write ${service}"
  else
    cat > "$service" <<SERVICE
[Unit]
Description=Typeless Clipbridge clipboard sync
After=default.target

[Service]
Type=simple
ExecStart=/bin/bash ${BIN_DIR}/tcb-clip-sync.sh
Restart=always
RestartSec=5
Environment=LANG=en_US.UTF-8
Environment=LC_CTYPE=en_US.UTF-8
Environment=TCB_PEERS=${PEERS_CSV}
Environment=TCB_INTERVAL=${POLL_INTERVAL}
Environment=TCB_STATE_DIR=${STATE_DIR}
Environment=TCB_LOG_PREFIX_LEN=${TCB_LOG_PREFIX_LEN:-0}

[Install]
WantedBy=default.target
SERVICE
    systemctl --user daemon-reload
    systemctl --user enable --now typeless-clipbridge-clip-sync.service
  fi
}

status_action() {
  if [[ -x "$BIN_DIR/tcb" ]]; then
    "$BIN_DIR/tcb" status
  else
    log "not installed at $PREFIX"
  fi
}

uninstall_action() {
  if [[ -x "$BIN_DIR/tcb" ]]; then
    "$BIN_DIR/tcb" uninstall
  else
    log "nothing to uninstall at $PREFIX"
  fi
}

main() {
  if [[ "$OS" == "unsupported" ]]; then
    fail "unsupported OS: $(uname -s). macOS is primary; Linux has best-effort clipboard sync."
  fi

  if [[ "$ACTION" == "status" ]]; then
    status_action
    exit 0
  fi
  if [[ "$ACTION" == "uninstall" ]]; then
    uninstall_action
    exit 0
  fi

  log "version=${VERSION} os=${OS} arch=$(uname -m)"
  prompt_for_peer_if_needed
  install_tailscale_if_needed
  install_linux_clipboard_deps
  install_assets

  if should_install_sync; then
    if [[ "$OS" == "macos" ]]; then
      install_macos_clip_sync
    else
      install_linux_clip_sync
    fi
  else
    log "clipboard sync skipped (no --peer provided)"
  fi

  if should_install_typeless; then
    install_macos_typeless_watch
  else
    log "Typeless watcher skipped"
  fi

  log "done"
  log "status: $BIN_DIR/tcb status"
  log "doctor: $BIN_DIR/tcb doctor"
}

main "$@"
