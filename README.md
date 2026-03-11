# MultiplexTerm

A native macOS terminal multiplexer GUI built with Zig and Cocoa. Wraps tmux with a modern dark UI for managing sessions, panes, and windows — designed for AI-assisted development workflows.

## Features

- Native macOS GUI with Vercel-style dark theme
- Tmux session management (create, rename, delete, switch)
- Smart session names (auto-detects running apps like NVim, Claude Code, etc.)
- Command palette (Cmd+K) for splits, windows, and pane control
- VT100/ANSI terminal emulation with 256-color and RGB support
- Text selection, copy/paste (Cmd+C/V)
- Mouse support (pane selection, scroll)

## Requirements

- macOS
- Zig 0.15+
- tmux

## Build

```
zig build
./zig-out/bin/mterm
```
