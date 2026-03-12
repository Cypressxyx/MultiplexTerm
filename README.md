# MultiplexTerm

A native macOS terminal multiplexer GUI built with Zig and Cocoa. Wraps tmux with a modern dark UI for managing sessions, panes, and windows — designed for AI-assisted development workflows.

**Website:** https://jfinite.com/multiplexterm/

## Features

- Native macOS GUI with 25 built-in themes (Vercel Dark, Gruvbox, Catppuccin, Nord, Dracula, and more)
- Tmux session management (create, rename, delete, switch)
- Smart session names (auto-detects running apps like NVim, Claude Code, etc.)
- Recent Projects sidebar with quick-launch into frequently visited directories
- Command palette (Cmd+K) for splits, windows, pane control, and theme selection
- VT100/ANSI terminal emulation with 256-color and RGB support
- Text selection, copy/paste (Cmd+C/V)
- Mouse support (pane selection, scroll)

## How It Works

```mermaid
graph TD
    subgraph GUI["macOS / Cocoa — src/platform/macos.m"]
        Sidebar["Sidebar\nSessions, + New, Cmd+K palette"]
        TermView["Terminal Rendering\ndrawTerminal, drawCursor"]
    end

    subgraph Bridge["Bridge Layer (Zig) — src/platform/bridge.zig"]
        BridgeTick["bridge_tick()"]
        BridgeKey["bridge_key_input()"]
        BridgeResize["bridge_resize()"]
        BridgeSession["bridge_select/create/kill_session()"]
    end

    subgraph Core["Core Modules"]
        PTY["PTY I/O\nsrc/pty.zig"]
        Tmux["Tmux Manager\nsrc/tmux/manager.zig"]
        Engine["Terminal Engine\nsrc/terminal/engine.zig"]
        Parser["VT Parser\nsrc/terminal/parser.zig"]
        Screen["Screen Model\nsrc/terminal/screen.zig"]
        State["App State\nsrc/state.zig"]
    end

    TmuxServer["tmux server\n(subprocess)"]

    Sidebar -->|"mouse click"| BridgeSession
    TermView -->|"NSTimer 60fps"| BridgeTick
    GUI -->|"keyDown"| BridgeKey
    GUI -->|"setFrameSize"| BridgeResize

    BridgeTick --> PTY
    BridgeTick --> Engine
    BridgeTick --> State
    BridgeKey --> PTY
    BridgeSession --> Tmux
    BridgeResize --> Engine

    PTY <-->|"read/write"| TmuxServer
    Tmux -->|"subprocess calls"| TmuxServer
    Engine --> Parser
    Engine --> Screen

    BridgeTick -->|"syncState every 30 ticks"| Tmux
    BridgeTick -->|"updateRenderCells"| TermView
```

### Data Flow

```mermaid
sequenceDiagram
    participant User
    participant GUI as macos.m
    participant Bridge as bridge.zig
    participant PTY as pty.zig
    participant Engine as engine.zig
    participant Tmux as tmux server

    Note over GUI,Tmux: Startup
    GUI->>Bridge: bridge_init()
    GUI->>Bridge: bridge_resize(cols, rows)
    Bridge->>PTY: openpty + spawn tmux
    PTY->>Tmux: tmux new-session -A

    Note over GUI,Tmux: Tick Loop (60fps)
    loop Every frame
        GUI->>Bridge: bridge_tick()
        Bridge->>PTY: poll + read
        PTY-->>Bridge: terminal output bytes
        Bridge->>Engine: process(bytes)
        Engine-->>Bridge: updated screen cells
        Bridge-->>GUI: BridgeCell array
        GUI->>GUI: drawRect
    end

    Note over GUI,Tmux: Key Input
    User->>GUI: keyDown
    GUI->>Bridge: bridge_key_input(bytes)
    Bridge->>PTY: write(bytes)
    PTY->>Tmux: input forwarded

    Note over GUI,Tmux: Session Exit
    Tmux-->>PTY: HUP
    Bridge->>Bridge: reattachOrQuit()
    Bridge->>Tmux: list-sessions
    Bridge->>PTY: new PTY + attach
```

## Install

### Homebrew (recommended)

```bash
brew tap Cypressxyx/multiplexterm
brew install --cask multiplexterm
```

### Build from source

Requirements: macOS, [Zig](https://ziglang.org/download/) 0.15+, [tmux](https://github.com/tmux/tmux) 3.0+

```bash
git clone https://github.com/Cypressxyx/MultiplexTerm.git
cd MultiplexTerm

# Build and run
zig build
./zig-out/bin/mterm

# Or install as macOS app (adds mTerm.app to /Applications)
zig build install-app
```

tmux is required:
```bash
brew install tmux
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+K | Command palette (split panes, new window, zoom, themes, etc.) |
| Cmd+C | Copy selection |
| Cmd+V | Paste |
| Cmd+Q | Quit |

## Themes

25 built-in themes with live preview — open **Cmd+K → Theme...** to browse and apply.

| | Dark | Light |
|---|---|---|
| **Vercel** | Vercel Dark *(default)* | |
| **Gruvbox** | Gruvbox Dark | Gruvbox Light |
| **Catppuccin** | Catppuccin Mocha | Catppuccin Latte |
| **Kanagawa** | Kanagawa | Kanagawa Light |
| **Nord** | Nord | |
| **Dracula** | Dracula | |
| **One** | One Dark | One Light |
| **Solarized** | Solarized Dark | Solarized Light |
| **Tokyo Night** | Tokyo Night | Tokyo Night Light |
| **Rosé Pine** | Rosé Pine | Rosé Pine Dawn |
| **Everforest** | Everforest Dark | Everforest Light |
| **Monokai** | Monokai Pro | |
| **Ayu** | Ayu Dark | Ayu Light |
| **Nightfox** | Nightfox | |
| **Synthwave** | Synthwave '84 | |
| **GitHub** | GitHub Dark | |

## Session Management

- Click a session in the sidebar to switch
- Click **+ New Session** to create one
- Double-click a session to rename
- Click **×** once to arm (turns red), click again to delete
- Right-click a session for context menu
- **Recent Projects** section shows frequently visited directories — click to open a new session there, **×** to remove
