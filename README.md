# Typeless Clipbridge

macOS-first clipboard bridge for Typeless dictation and Tailscale-connected machines.

## One-Line Install

Default installer:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh
```

Install clipboard sync against one peer:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh -s -- --peer user@100.x.x.x
```

Install on a Mac that has Typeless and a Tailscale peer:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i | sh -s -- --peer user@100.x.x.x --typeless
```

The installer itself falls back across jsDelivr, Fastly jsDelivr, Gcore jsDelivr, and GitHub raw for every later download. For a single paste command with initial mirror fallback too:

```bash
sh -c 't=$(mktemp); for u in https://cdn.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i https://fastly.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i https://gcore.jsdelivr.net/gh/thedaosheng/typeless-clipbridge@main/i https://raw.githubusercontent.com/thedaosheng/typeless-clipbridge/main/i; do curl -fsSL "$u" -o "$t" && sh "$t" "$@"; r=$?; rm -f "$t"; exit $r; done; rm -f "$t"; exit 1' sh
```

## What It Does

- Detects macOS or Linux.
- Detects Tailscale and can install it when practical.
- Installs a per-user clipboard sync daemon.
- On macOS, installs a Typeless SQLite watcher when Typeless is present or `--typeless` is passed.
- Provides a local `tcb` command at `~/.typeless-clipbridge/bin/tcb`.

The primary supported platform is macOS. Linux support is best-effort for peer clipboard sync and uses Wayland, X11, or a file mirror fallback.

## Commands

```bash
~/.typeless-clipbridge/bin/tcb status
~/.typeless-clipbridge/bin/tcb doctor
~/.typeless-clipbridge/bin/tcb logs
~/.typeless-clipbridge/bin/tcb logs typeless
~/.typeless-clipbridge/bin/tcb restart
~/.typeless-clipbridge/bin/tcb print-latest
```

## Design Notes

This follows the OpenClaw-style deployment shape: a tiny public curl entrypoint delegates to a layered installer, then the installer handles OS detection, dependency checks, daemon installation, and doctor/status commands.

Tailscale is the network substrate. Linux can use the official Tailscale install script; macOS is guided toward the official Standalone app, with Homebrew cask as an automated path when Homebrew is present.
