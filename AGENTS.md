# MultiplexTerm — AGENTS.md

## Project Overview

MultiplexTerm (CLI: `mterm`) is a native macOS GUI terminal that wraps tmux. It provides a modern sidebar UI for session management, a command palette, and full terminal emulation — built for AI-assisted development workflows.

**Stack**: Zig 0.15 + Objective-C/Cocoa (AppKit) + tmux

## Agent Rules

1. **Always update this file** when adding new functionality — document new files, data flows, conventions, and pitfalls.
2. **Always add unit tests** for every change. Run `zig build test` to verify before committing.
3. **Update README.md** when adding user-facing features (new shortcuts, UI changes, etc.).
4. **Run `zig build`** to verify compilation before committing.
5. **Run `zig build lint`** to check for lint issues before committing.

## Setup & Build

```bash
# Build
zig build

# Run
./zig-out/bin/mterm

# Install as macOS .app bundle to /Applications
zig build install-app

# Run tests
zig build test

# Lint (requires zlint: https://github.com/DonIsaac/zlint)
zig build lint
```

### Requirements
- macOS
- Zig 0.15+
- tmux 3.0+

## Architecture

```mermaid
graph TD
    subgraph GUI["macOS / Cocoa — src/platform/macos.m"]
        Sidebar["Sidebar\nSessions, Remote, Recent Projects"]
        TermView["Terminal Rendering\ndrawTerminal, drawCursor"]
        Palette["Command Palette\nCmd+K, themes, add SSH host"]
        DragDrop["Drag & Drop\nFile path paste"]
    end

    subgraph Bridge["Bridge Layer (Zig) — src/platform/bridge.zig"]
        BridgeTick["bridge_tick()"]
        BridgeKey["bridge_key_input()"]
        BridgeResize["bridge_resize()"]
        BridgeSession["bridge_select/create/kill_session()"]
        BridgeSSH["bridge_*ssh*() / bridge_is_ssh_session()"]
    end

    subgraph Core["Core Modules"]
        PTY["PTY I/O\nsrc/pty.zig"]
        Tmux["Tmux Manager\nsrc/tmux/manager.zig"]
        Engine["Terminal Engine\nsrc/terminal/engine.zig"]
        Parser["VT Parser\nsrc/terminal/parser.zig"]
        Screen["Screen Model\nsrc/terminal/screen.zig"]
        State["App State\nsrc/state.zig"]
        SSH["SSH Config\nsrc/ssh.zig"]
    end

    TmuxServer["tmux server\n(subprocess)"]
    RemoteHost["Remote SSH host"]

    Sidebar -->|"mouse click"| BridgeSession
    Sidebar -->|"SSH click"| BridgeSSH
    TermView -->|"NSTimer 60fps"| BridgeTick
    GUI -->|"keyDown"| BridgeKey
    GUI -->|"setFrameSize"| BridgeResize
    DragDrop -->|"file path"| BridgeKey

    BridgeTick --> PTY
    BridgeTick --> Engine
    BridgeTick --> State
    BridgeKey --> PTY
    BridgeSession --> Tmux
    BridgeSSH --> SSH
    BridgeSSH --> Tmux
    BridgeResize --> Engine

    PTY <-->|"read/write"| TmuxServer
    Tmux -->|"subprocess calls"| TmuxServer
    Engine --> Parser
    Engine --> Screen
    SSH -->|"ssh subprocess"| RemoteHost

    BridgeTick -->|"syncState every 30 ticks"| Tmux
    BridgeTick -->|"updateRenderCells"| TermView
```

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

    Note over GUI,Tmux: SSH Remote Session
    User->>GUI: click host in REMOTE
    GUI->>Bridge: bridge_toggle_ssh_host()
    Bridge->>Bridge: spawn probe thread
    Bridge-->>Bridge: ssh host tmux list-sessions
    User->>GUI: click + New Session
    GUI->>Bridge: bridge_create_ssh_shell()
    Bridge->>Tmux: new-session ssh host
    Note right of Bridge: Session named "ssh_host-N"<br/>shown under REMOTE, not SESSIONS

    Note over GUI,Tmux: Session Exit
    Tmux-->>PTY: HUP
    Bridge->>Bridge: reattachOrQuit()
    Bridge->>Tmux: list-sessions
    Bridge->>PTY: new PTY + attach
```

## File Map

| File | Purpose |
|------|---------|
| `src/main.zig` | Entry point. Imports bridge, calls `platform_run()` |
| `src/platform/macos.m` | ObjC/Cocoa GUI: window, sidebar, terminal rendering, input, command palette |
| `src/platform/bridge.zig` | C FFI bridge: connects GUI ↔ PTY ↔ tmux ↔ terminal engine. All `export fn bridge_*` functions live here |
| `src/pty.zig` | PTY management: `openpty`, `fork`, `exec`, size, read/write |
| `src/terminal/parser.zig` | VT100/ANSI escape sequence parser with UTF-8 support |
| `src/terminal/engine.zig` | Connects parser events to screen model. Handles CSI sequences, DEC private modes, scroll regions |
| `src/terminal/screen.zig` | Screen buffer model: cells, cursor, scroll regions, alt screen, attributes |
| `src/state.zig` | App state: session list, active session, sidebar visibility |
| `src/tmux/manager.zig` | Tmux subprocess commands: list/create/kill/rename sessions, list windows/panes, create SSH sessions |
| `src/ssh.zig` | SSH config parser (`~/.ssh/config`) and remote tmux session discovery via SSH subprocess |
| `build.zig` | Build config: compiles Zig + ObjC, links Cocoa framework |

## E2E Data Flow

### Startup
1. `main()` → `platform_run()` (ObjC)
2. ObjC creates NSWindow, STTerminalView, calls `bridge_init()`
3. `bridge_init()` creates TmuxManager, AppState
4. First `setFrameSize` → `recalcTermSize` → `bridge_resize(cols, rows)`
5. `bridge_resize` checks for existing tmux sessions on first invocation (deferred init)
6. If existing sessions found: `startPtyAttach()` attaches to first session
7. If no existing sessions: stays in empty state, shows "Start New Session" button
8. Hides tmux status bar, enables mouse mode, clears CLAUDECODE from tmux env
9. NSTimer starts at 60fps calling `tick:` → `bridge_tick()`

### Tick Loop (60fps)
1. `bridge_tick()` polls PTY master fd for data
2. Reads PTY output → feeds to `TerminalEngine.process()` → parser → screen model
3. Every 30 ticks (~0.5s): `syncState()` refreshes session list from tmux, updates display names
4. If redraw needed: `updateRenderCells()` copies screen cells to BridgeCell array
5. ObjC `drawRect:` reads BridgeCell array and renders via Core Graphics

### Key Input
1. ObjC `keyDown:` → handles Cmd+K (palette), Cmd+C/V (copy/paste), Option+key (Meta/ESC+char)
2. Arrow keys, special keys → send VT escape sequences
3. Regular keys → `bridge_key_input()` → PTY write
4. Leader key (Ctrl+A) → `handleAppKey()` for session switching (j/k/n/x/b)

### Mouse Input
1. Click in sidebar → `bridge_select_session()`, `bridge_kill_session()`, `bridge_create_session()`
2. Click in terminal → sends xterm mouse protocol (ESC [ M) for tmux pane selection
3. Drag in terminal → text selection (highlighted blue)
4. Scroll wheel → xterm mouse wheel events (tmux mouse mode)

### SSH Remote Sessions
1. Sidebar shows "REMOTE" section (between New Session button and Recent Projects) — always visible
2. Hosts from `~/.ssh/config` (via `ssh_mod.parseSshConfig()`, skips wildcards) + manual hosts from `~/.mterm/ssh_hosts`
3. Click disconnected host → spawns background thread running `ssh -o BatchMode=yes host tmux list-sessions`
4. If successful, host status = connected, expanded view shows: active SSH sessions → remote tmux sessions → "+ New Session"
5. Click remote tmux session → `tmux.createSshSession()` creates local tmux session running `ssh host -t 'tmux attach-session -t session'`
6. Click "+ New Session" → `bridge_create_ssh_shell()` creates local tmux session running `ssh host` (plain shell)
7. **SSH sessions show under REMOTE, not SESSIONS**: all SSH-created sessions use `ssh_` name prefix (e.g., `ssh_host/session`, `ssh_host-N`), filtered from SESSIONS list via `bridge_is_ssh_session()`, displayed under their host in REMOTE via `bridge_get_ssh_active_count/display/idx()`
8. Active SSH sessions show with green dot + accent bar when selected; remote tmux sessions show dimmer (not yet connected)
9. "+ Add Host" button opens in-app palette card (`paletteMode=2`) for manual host entry
10. Status dots: green=connected, yellow=connecting, red=error, hollow=disconnected

### Session Exit / HUP
1. PTY HUP detected → `reattachOrQuit()`
2. Checks for remaining tmux sessions
3. If sessions exist: opens new PTY, attaches to first available session
4. If no sessions: sets `g_started = false` → returns to empty state with "Start New Session" button

## Code Style

- Zig: standard library conventions, snake_case for functions/vars
- ObjC: Apple conventions, camelCase methods, `ST` prefix for custom classes
- All bridge functions: `export fn bridge_*` with `callconv(.c)`
- No external dependencies beyond Zig stdlib + macOS system frameworks

## Key Conventions

### Zig ↔ ObjC FFI
- BridgeCell is `extern struct` with explicit padding for C compatibility
- Colors use `u32`: `0xFFFFFFFF` = default, else `0x00RRGGBB`
- Attributes packed in `u8`: bit0=bold, bit1=underline, bit2=reverse, bit3=dim, bit4=italic

### Terminal Emulation
- Parser states: ground, escape, CSI, OSC, DCS, UTF-8, charset
- Engine handles: cursor movement, SGR attributes, scroll regions, alt screen, DEC private modes (1, 7, 25, 1047, 1048, 1049, 2004)
- Screen: deferred line wrap, cursor save/restore, insert/delete line/char

### Display Names
- `computeDisplayName()` in bridge.zig determines sidebar label per session
- Priority: **user-renamed session name** (if not auto-generated) → notable app name (via `prettyName()`) → raw command → directory basename → session name
- `isAutoNameWithPath()` detects auto-generated names: bare digits, `session-N`, `mterm`, `<cwd>-N`, `<session_path>-N`, `<HOME>-N` — anything else is treated as user-renamed
- `isShell()` recognizes: zsh, bash, fish, sh, dash, tcsh, ksh, tmux, login
- `isVersionString()` detects version-like commands (e.g. "2.1.74") that some tools set as process title — maps to "Claude Code"
- Sessions are sorted by `session_created` timestamp (newest first, newest at top)
- `prettyName()` maps: nvim→"NVim", claude→"Claude Code", python3→"Python", node→"Node.js", etc.

### Recent Projects
- Sidebar shows a "RECENT PROJECTS" section below the "+ New Session" button
- Tracks directories from active tmux sessions via `pane_current_path`
- Persisted to `~/.mterm/recent_projects` (one path per line, max 10 entries)
- Clicking a recent project creates a new tmux session in that directory and switches to it
- × button on hover removes a project from the list
- Section always visible with "Nothing yet" placeholder when empty
- Also shown in empty state (no sessions) below the "Start New Session" button
- Backend: `loadRecentProjects()`, `saveRecentProjects()`, `addRecentProject()` in bridge.zig
- FFI: `bridge_get_recent_project_count/display/path()`, `bridge_create_session_in_dir()`, `bridge_remove_recent_project()`
- Manager: `createSessionInDir()` in tmux/manager.zig uses `tmux new-session -d -s <name> -c <dir>`

### Theme System
- 25 built-in themes selectable via Cmd+K → Theme... submenu
- Themes: Vercel Dark (default), Gruvbox Dark/Light, Catppuccin Mocha/Latte, Kanagawa/Light, Nord, Dracula, One Dark/Light, Solarized Dark/Light, Tokyo Night/Light, Rosé Pine/Dawn, Everforest Dark/Light, Monokai Pro, Ayu Dark/Light, Nightfox, Synthwave '84, GitHub Dark
- `ThemeDef` struct: name, bg, fg, sidebar, border, accent, green (all `uint32_t` hex)
- `applyTheme(idx)` computes derived colors (textDim, textMuted, selectedBg, hoverBg) via `blendHex()`
- `g_currentTheme` tracks active theme index; `g_savedTheme` saves the pre-preview theme for revert
- **Live preview**: navigating themes (keyboard or mouse hover) calls `applyTheme()` immediately; Escape/Back reverts to `g_savedTheme`
- `paletteMode`: 0=commands, 1=themes, 2=add SSH host — controls which view `drawPalette` renders
- Both command and theme palette modes have a search bar for filtering items by name (case-insensitive substring match)
- `paletteSearchText` (NSMutableString) holds the current search query; cleared on mode switch, open/close
- `paletteSelection` is always an index into the *filtered* list, not the absolute list; mapped back via `getFilteredCommandIndices:`/`getFilteredThemeIndices:`
- In theme mode, backspace deletes search text; when search is empty, backspace goes back to commands
- Fonts: SF Mono (terminal), SF Pro (UI), Menlo (italic/bold-italic)

### Command Palette (Cmd+K)
- Floating card over terminal — no full-screen overlay (dark overlays make dark themes invisible)
- Card uses drop shadow (`NSShadow`) for contrast against terminal content
- All palette colors use theme globals (`g_sidebarBg`, `g_border`, `g_selectedBg`, `g_text`, etc.) — never hardcoded hex
- Three modes: commands (`paletteMode=0`, 9 items), theme picker (`paletteMode=1`, 25 scrollable items), add SSH host (`paletteMode=2`, text input)
- Commands mode: up/down navigate, Enter executes (or enters theme submenu for last item), Escape closes
- Theme mode: up/down navigate with live preview, Enter confirms, Escape/Backspace reverts and goes back
- Add SSH host mode: uses search bar as input field, Enter adds host, Escape cancels — no NSAlert
- Mouse: click to select, hover to highlight (and preview in theme mode), scroll wheel in theme picker
- Cmd+K while in theme preview reverts to saved theme before closing

### Drag and Drop
- Dragging files from Finder into the terminal pastes their file paths (shell-escaped)
- Multiple files are space-separated
- Implemented via `NSDraggingDestination` protocol on STTerminalView
- Registered for `NSPasteboardTypeFileURL` in `initWithFrame`
- Special characters (spaces, quotes, parens) are escaped for shell safety

## Testing

```bash
# Unit tests
zig build test

# Manual testing checklist
# - Launch mterm, verify sidebar shows sessions
# - Open nvim → sidebar should show "NVim"
# - Cmd+K → command palette opens, split pane works
# - Click tmux pane → pane gets focus
# - Type exit → app reattaches to remaining session (not crash)
# - Option+F → forward word (not crash)
# - Double-click terminal → selects line
# - Cmd+C/V → copy/paste works
# - Cmd+K → Theme... → theme picker opens, can select theme with click or keyboard
# - Scroll, hover, and back button work in theme picker
# - Recent projects section appears in sidebar after visiting directories
# - Clicking a recent project creates a new session in that directory
# - Running Claude Code → sidebar should show "Claude Code", not a version number
# - SSH: REMOTE section shows hosts from ~/.ssh/config
# - SSH: Click host → status changes to connecting, then shows remote tmux sessions
# - SSH: Click remote session → creates local tmux session with SSH attach, appears in sessions list
# - SSH: Click "+ Add Host" → opens in-app input card (not NSAlert), type host and press Enter
# - Drag a file from Finder into terminal → file path is pasted (shell-escaped)
# - Drag multiple files → all paths pasted space-separated

# Logs
cat /tmp/mterm.log
```

## Common Pitfalls

- **ESC byte ordering**: In parser.zig, `byte == 0x1b` MUST be checked before `byte < 0x20` or all escape sequences break
- **PTY HUP on session kill**: Must switch to another session BEFORE killing, or tmux client exits and PTY gets HUP
- **Deferred PTY init**: On first `bridge_resize`, checks for existing tmux sessions — attaches if found, shows empty state if not. PTY only starts when sessions exist or user clicks "Start New Session"
- **tmux env inheritance**: CLAUDECODE env var must be cleared at both PTY child level (`unsetenv`) and tmux level (`-e CLAUDECODE=`, `set-environment -g -u`)
- **Display name early returns**: `syncState()` must always call `updateDisplayNames()` — don't return early before it
- **Cells bounds**: `drawTerminal` must bounds-check cell index against `bridge_get_cell_count()` to prevent crashes during resize
- **Option key**: Option+key sends ESC+char (Meta), not the macOS Unicode glyph — terminal apps expect Meta behavior
- **Palette overlay**: Do NOT use a full-screen semi-transparent overlay behind the command palette — on dark themes it makes the terminal content invisible. Use a drop shadow on the card instead.
- **Palette colors**: All palette UI colors must use theme globals (`g_sidebarBg`, `g_border`, etc.), never hardcoded hex — otherwise the palette becomes invisible on certain themes
- **Theme preview revert**: When entering theme picker, save `g_currentTheme` to `g_savedTheme`. ALL exit paths (Escape, Backspace, Back click, click outside, Cmd+K toggle) must call `applyTheme(g_savedTheme)` to revert. Only Enter/click-on-theme confirms without revert.
- **Finder/Raycast launch PATH**: macOS GUI apps get a minimal PATH (`/usr/bin:/bin`). Homebrew paths (`/opt/homebrew/bin`, `/usr/local/bin`) must be added at startup in `applicationDidFinishLaunching` or tmux won't be found.
- **Finder/Raycast launch cwd**: When launched from Finder/Raycast, cwd is `/`. `basename("/")` is empty, which gives tmux an invalid session name. ALL code that derives names from cwd (`startPty`, `bridge_create_session`) must fall back to HOME basename or "mterm".
- **Finder/Raycast launch locale**: Without `LANG`/`LC_ALL` set, tmux uses VT100 line-drawing escape sequences instead of UTF-8 box-drawing characters, causing garbled rendering. Must set `LANG=en_US.UTF-8` at startup.
- **Sidebar layout consistency**: `drawSidebar`, `mouseDown:`, `mouseMoved:`, and `rightMouseDown:` must all compute the same flow layout: sessions (skip SSH) → "+ New Session" button → SSH remote section (active SSH sessions → remote tmux sessions → "+ New Session" per host → "+ Add Host") → recent projects. Never bottom-anchor the button.
- **SSH probe thread safety**: The SSH connection probe runs in a background thread (`sshProbeThreadFn`). It writes to `g_ssh_hosts[idx]` fields and sets `status = .connected` LAST so the main thread sees consistent state. Uses `std.heap.page_allocator` (thread-safe) for the subprocess.
- **SSH session naming**: All SSH sessions use `ssh_` prefix (e.g., `ssh_host/session`, `ssh_host-3`). `bridge_is_ssh_session()` checks this prefix. `isSshSessionForHost()` matches sessions to hosts by checking `ssh_<hostname>/` or `ssh_<hostname>-`. These sessions are hidden from SESSIONS and shown under REMOTE.
- **SSH session sidebar layout consistency**: `drawSidebar`, `mouseDown:`, `mouseMoved:`, and `rightMouseDown:` must all walk session rows with `bridge_is_ssh_session()` skip — never compute `sessionsEnd = listTop + count * kSessionRowH` since SSH sessions are excluded.
- **No NSAlert for SSH host input**: The "Add Host" prompt MUST use the in-app palette card (`paletteMode=2`), not NSAlert — native macOS dialogs don't match the custom-drawn UI style.
- **Drag-and-drop path escaping**: File paths from Finder drag must be shell-escaped (spaces, quotes, parens) before sending to PTY, or commands will break on paths with special characters.
