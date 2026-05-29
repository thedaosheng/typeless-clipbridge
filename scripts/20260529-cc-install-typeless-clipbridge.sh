#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "typeless-clipbridge currently supports macOS only." >&2
  exit 1
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Install Typeless Clipbridge as a macOS LaunchAgent.

Optional environment variables:
  TYPELESS_DB_PATH                       Typeless SQLite path
  TYPELESS_CLIPBRIDGE_INTERVAL           Poll interval seconds, default 1
  TYPELESS_CLIPBRIDGE_DELAYS             Copy retry delays, default "0.8 2 4 8 15"
  TYPELESS_REMOTE_CLIPBOARD_ENABLED      Set 1 to push text to a remote Mac
  TYPELESS_REMOTE_CLIPBOARD_USER         Remote macOS user
  TYPELESS_REMOTE_CLIPBOARD_HOST         Remote macOS host/IP
  TYPELESS_REMOTE_CLIPBOARD_KEY          SSH identity path

Example:
  TYPELESS_REMOTE_CLIPBOARD_ENABLED=1 \
  TYPELESS_REMOTE_CLIPBOARD_USER=remote-user \
  TYPELESS_REMOTE_CLIPBOARD_HOST=mac-mini.local \
  bash 20260529-cc-install-typeless-clipbridge.sh
HELP
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_WATCHER="${SCRIPT_DIR}/20260529-cc-typeless-clipbridge.zsh"

APP_SUPPORT="${HOME}/Library/Application Support/TypelessClipbridge"
LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"
WATCHER_PATH="${APP_SUPPORT}/typeless-clipbridge.zsh"
PLIST_PATH="${LAUNCH_AGENTS}/com.agentbus.typeless-clipbridge.plist"
LABEL="com.agentbus.typeless-clipbridge"

mkdir -p "${APP_SUPPORT}" "${LAUNCH_AGENTS}"
cp "${SOURCE_WATCHER}" "${WATCHER_PATH}"
chmod +x "${WATCHER_PATH}"

TYPELESS_DB_PATH="${TYPELESS_DB_PATH:-${HOME}/Library/Application Support/Typeless/typeless.db}"
TYPELESS_CLIPBRIDGE_INTERVAL="${TYPELESS_CLIPBRIDGE_INTERVAL:-1}"
TYPELESS_CLIPBRIDGE_DELAYS="${TYPELESS_CLIPBRIDGE_DELAYS:-0.8 2 4 8 15}"
TYPELESS_REMOTE_CLIPBOARD_ENABLED="${TYPELESS_REMOTE_CLIPBOARD_ENABLED:-0}"
TYPELESS_REMOTE_CLIPBOARD_USER="${TYPELESS_REMOTE_CLIPBOARD_USER:-}"
TYPELESS_REMOTE_CLIPBOARD_HOST="${TYPELESS_REMOTE_CLIPBOARD_HOST:-}"
TYPELESS_REMOTE_CLIPBOARD_KEY="${TYPELESS_REMOTE_CLIPBOARD_KEY:-${HOME}/.ssh/id_ed25519}"

cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>${WATCHER_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${APP_SUPPORT}/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${APP_SUPPORT}/stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>LANG</key>
    <string>en_US.UTF-8</string>
    <key>LC_CTYPE</key>
    <string>en_US.UTF-8</string>
    <key>TYPELESS_DB_PATH</key>
    <string>${TYPELESS_DB_PATH}</string>
    <key>TYPELESS_CLIPBRIDGE_INTERVAL</key>
    <string>${TYPELESS_CLIPBRIDGE_INTERVAL}</string>
    <key>TYPELESS_CLIPBRIDGE_DELAYS</key>
    <string>${TYPELESS_CLIPBRIDGE_DELAYS}</string>
    <key>TYPELESS_REMOTE_CLIPBOARD_ENABLED</key>
    <string>${TYPELESS_REMOTE_CLIPBOARD_ENABLED}</string>
    <key>TYPELESS_REMOTE_CLIPBOARD_USER</key>
    <string>${TYPELESS_REMOTE_CLIPBOARD_USER}</string>
    <key>TYPELESS_REMOTE_CLIPBOARD_HOST</key>
    <string>${TYPELESS_REMOTE_CLIPBOARD_HOST}</string>
    <key>TYPELESS_REMOTE_CLIPBOARD_KEY</key>
    <string>${TYPELESS_REMOTE_CLIPBOARD_KEY}</string>
  </dict>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "${PLIST_PATH}"
/bin/zsh -n "${WATCHER_PATH}"

uid="$(id -u)"
/bin/launchctl bootout "gui/${uid}" "${PLIST_PATH}" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/${uid}" "${PLIST_PATH}"
/bin/launchctl enable "gui/${uid}/${LABEL}"
/bin/launchctl kickstart -k "gui/${uid}/${LABEL}"

echo "Installed ${LABEL}"
echo "Status: launchctl print gui/${uid}/${LABEL}"
echo "Log: ${APP_SUPPORT}/watcher.log"
