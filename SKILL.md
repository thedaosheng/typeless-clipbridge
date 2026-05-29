---
name: typeless-clipbridge
description: Use this macOS-only skill when the user wants Typeless dictation results automatically copied to the local clipboard, pushed into a shared clipboard workflow, or debugged after RightCtrl-triggered Typeless dictation finishes.
---

# Typeless Clipbridge

## Overview

Typeless Clipbridge is a macOS-first workflow for turning completed Typeless dictation results into reliable clipboard updates and propagating clipboard text across Tailscale-connected machines. On macOS, it watches Typeless' local SQLite history, copies new `refined_text` values to the clipboard with delayed verification retries, and can participate in cross-device clipboard sync over SSH.

The public installer also provides an OpenClaw-style one-line deployment path for Tailscale-connected clipboard sync:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh
curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh -s -- --peer user@100.x.x.x
```

Use this skill when the user mentions Typeless, RightCtrl-triggered dictation, shared clipboards, `pbcopy`, `pbpaste`, Tailscale, launchd, systemd user services, or Typeless output not appearing in a clipboard-based cross-device setup.

## Platform Boundary

The Typeless watcher currently supports macOS only because it depends on Typeless' macOS application data path and macOS clipboard tools.

The clipboard sync daemon supports macOS first and Linux best-effort. Linux uses Wayland clipboard tools, X11 clipboard tools, or a file mirror fallback when no GUI clipboard is available.

## Included Scripts

- `scripts/20260529-cc-install-typeless-clipbridge.sh`: installs the watcher as a user LaunchAgent.
- `scripts/20260529-cc-typeless-clipbridge.zsh`: polls Typeless SQLite history and copies new results to the clipboard.
- `scripts/20260529-cc-clipboard-sync-macos.sh`: optional UTF-8-safe one-way clipboard pull template for Mac-to-Mac shared clipboard setups.
- `i`: shortest public curl entrypoint.
- `install.sh`: stable bootstrap that fetches the layered installer.
- `scripts/tcb-install.sh`: OS detection, dependency checks, Tailscale handling, service installation.
- `scripts/tcb-clip-sync.sh`: cross-peer clipboard sync daemon.
- `scripts/tcb`: local status, doctor, logs, restart, and uninstall helper.

## One-Line Install Workflow

Use the shortest entrypoint for normal deployment:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh
```

Use `--peer` to sync with another Tailscale-reachable machine over SSH:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh -s -- --peer user@100.x.x.x
```

On macOS, pass `--typeless` to force-install the Typeless watcher even if the database has not been created yet:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh -s -- --peer user@100.x.x.x --typeless
```

The entrypoint and installer fall back across jsDelivr, Fastly jsDelivr, Gcore jsDelivr, and GitHub raw so deployment does not depend on direct access to `raw.githubusercontent.com`.

After installation, use:

```bash
~/.typeless-clipbridge/bin/tcb status
~/.typeless-clipbridge/bin/tcb doctor
~/.typeless-clipbridge/bin/tcb logs
```

## Install Workflow

The legacy Typeless-only installer remains available for direct macOS watcher installs.

1. Confirm macOS and required tools:

```bash
uname -s
command -v sqlite3 pbcopy pbpaste launchctl plutil
test -f "$HOME/Library/Application Support/Typeless/typeless.db"
```

2. Install the LaunchAgent from the skill root:

```bash
bash scripts/20260529-cc-install-typeless-clipbridge.sh
```

The installer writes:

- Watcher script: `$HOME/Library/Application Support/TypelessClipbridge/typeless-clipbridge.zsh`
- LaunchAgent: `$HOME/Library/LaunchAgents/com.agentbus.typeless-clipbridge.plist`
- Logs: `$HOME/Library/Application Support/TypelessClipbridge/watcher.log`

3. For a remote Mac clipboard push, pass environment variables during install:

```bash
TYPELESS_REMOTE_CLIPBOARD_ENABLED=1 \
TYPELESS_REMOTE_CLIPBOARD_USER=remote-user \
TYPELESS_REMOTE_CLIPBOARD_HOST=remote-mac.local \
TYPELESS_REMOTE_CLIPBOARD_KEY="$HOME/.ssh/id_ed25519" \
bash scripts/20260529-cc-install-typeless-clipbridge.sh
```

Keep remote settings generic in reusable docs and public repos. Do not hardcode personal hostnames, Tailscale IPs, account names, or private key paths beyond placeholder examples.

## Verify Workflow

1. Check launchd state:

```bash
launchctl print "gui/$(id -u)/com.agentbus.typeless-clipbridge"
```

2. Check the latest Typeless row the watcher can see:

```bash
scripts/20260529-cc-typeless-clipbridge.zsh --print-latest
```

3. Ask the user to trigger Typeless normally, usually with RightCtrl, and speak a short phrase. Then compare:

```bash
pbpaste
tail -n 80 "$HOME/Library/Application Support/TypelessClipbridge/watcher.log"
```

The first run seeds the latest existing Typeless row without copying it. A new Typeless result after the watcher starts should be queued, copied, and verified.

## How It Works

The watcher polls `history_v2` and `history` in Typeless' SQLite database:

- Text source: non-empty `refined_text`
- Accepted statuses: `completed` and `transcript`
- Sort key: `COALESCE(updated_at, created_at, '')`
- Clipboard command: `/usr/bin/pbcopy`
- Verification command: `/usr/bin/pbpaste`

It writes the last processed key to `$HOME/Library/Application Support/TypelessClipbridge/last-key`. Delayed retries are controlled by `TYPELESS_CLIPBRIDGE_DELAYS`, defaulting to `0.8 2 4 8 15`, which helps when Typeless or another clipboard daemon writes to the clipboard shortly after dictation completes.

## Optional Mac-to-Mac Clipboard Sync

Use `scripts/20260529-cc-clipboard-sync-macos.sh` as a template when the user already has a shared clipboard daemon or wants a UTF-8-safe Mac-to-Mac pull loop:

```bash
PEER_USER=remote-user \
PEER_HOST=remote-mac.local \
PEER_KEY="$HOME/.ssh/id_ed25519" \
bash scripts/20260529-cc-clipboard-sync-macos.sh
```

If this is converted into a LaunchAgent, always set `LANG=en_US.UTF-8` and `LC_CTYPE=en_US.UTF-8` in the plist. Missing UTF-8 locale variables are a common cause of Chinese text becoming corrupted or empty when `pbcopy`, `pbpaste`, and SSH run under launchd.

## Troubleshooting

- `seeded` appears but nothing copied: this is expected on first launch. Trigger a fresh Typeless dictation result.
- `typeless.db` missing: check whether Typeless is installed and whether the user is running the same macOS account.
- Chinese text is corrupted or blank: verify `LANG` and `LC_CTYPE` are set to `en_US.UTF-8` in every LaunchAgent and remote SSH command path.
- Remote Mac clipboard does not update: verify SSH works non-interactively with `BatchMode=yes`, the key exists, and the remote has `/usr/bin/pbcopy`.
- Clipboard is overwritten after copying: increase `TYPELESS_CLIPBRIDGE_DELAYS` and reinstall so delayed verification retries run longer.
- No rows show in `--print-latest`: inspect the Typeless database schema with `sqlite3 "$HOME/Library/Application Support/Typeless/typeless.db" ".schema"` before changing queries.

## Safety Rules

- Do not run the install script on non-macOS systems.
- Do not overwrite, unload, or delete unrelated clipboard LaunchAgents unless the user explicitly asks.
- Do not copy empty Typeless rows.
- Do not commit personal IP addresses, hostnames, usernames, or private key material into a reusable skill repository.
- Prefer testing with the user's real Typeless trigger. Synthetic SQLite rows can be useful, but clean them up and avoid treating them as proof that Typeless itself finished correctly.
