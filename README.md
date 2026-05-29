# Typeless Clipbridge

macOS-first clipboard bridge for Typeless dictation and Tailscale-connected machines.

## One-Line Install

Default installer:

```bash
curl -fsSL https://thedaosheng.github.io/t | sh
```

Install clipboard sync against one peer:

```bash
curl -fsSL https://thedaosheng.github.io/t | sh -s -- --peer user@100.x.x.x
```

Install on a Mac that has Typeless and a Tailscale peer:

```bash
curl -fsSL https://thedaosheng.github.io/t | sh -s -- --peer user@100.x.x.x --typeless
```

Readable alias:

```bash
curl -fsSL https://thedaosheng.github.io/tcb | sh
```

The short endpoint and the installer fall back across jsDelivr, Fastly jsDelivr, Gcore jsDelivr, and GitHub raw for every later download.

## What It Does

- Detects macOS or Linux.
- Detects Tailscale and can install it when practical: official Linux installer, Homebrew cask, or the official macOS `.pkg`.
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

Tailscale is the network substrate. Linux can use the official Tailscale install script; macOS uses Homebrew cask when available and otherwise downloads the official Standalone `.pkg` from `pkgs.tailscale.com`.
