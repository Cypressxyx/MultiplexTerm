const std = @import("std");
const posix = std.posix;
const Pty = @import("../pty.zig").Pty;
const TmuxManager = @import("../tmux/manager.zig").TmuxManager;
const AppState = @import("../state.zig").AppState;
const state_mod = @import("../state.zig");
const TerminalEngine = @import("../terminal/engine.zig").TerminalEngine;
const screen_mod = @import("../terminal/screen.zig");

pub const BridgeCell = extern struct {
    ch: u32 = ' ',
    fg: u32 = 0xFFFFFFFF, // 0xFFFFFFFF=default, else 0x00RRGGBB
    bg: u32 = 0xFFFFFFFF,
    attrs: u8 = 0, // bit0=bold, bit1=underline, bit2=reverse, bit3=dim, bit4=italic
    _pad: [3]u8 = .{ 0, 0, 0 },
};

const CTRL_A = 0x01;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var g_allocator: std.mem.Allocator = undefined;
var g_pty: ?Pty = null;
var g_engine: ?TerminalEngine = null;
var g_tmux: ?TmuxManager = null;
var g_state: ?AppState = null;
var g_cells: ?[]BridgeCell = null;
var g_leader: bool = false;
var g_redraw: bool = true;
var g_running: bool = true;
var g_sync_ctr: u32 = 0;

var g_started: bool = false;
var g_checked: bool = false; // whether we've checked for existing sessions on startup
var g_initial_cols: u16 = 80;
var g_initial_rows: u16 = 24;
var g_log_file: ?std.fs.File = null;

fn logInit() void {
    g_log_file = std.fs.cwd().createFile("/tmp/mterm.log", .{ .truncate = true }) catch null;
    logMsg("MultiplexTerm started");
}

fn logMsg(msg: []const u8) void {
    const f = g_log_file orelse return;
    f.writeAll(msg) catch {};
    f.writeAll("\n") catch {};
}

fn logFmt(comptime fmt: []const u8, args: anytype) void {
    const f = g_log_file orelse return;
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt ++ "\n", args) catch return;
    f.writeAll(msg) catch {};
}

export fn bridge_init() callconv(.c) u8 {
    g_allocator = gpa.allocator();
    logInit();

    var tmux = TmuxManager.init(g_allocator);
    if (!tmux.isAvailable()) {
        logMsg("tmux not available");
        return 1;
    }
    g_tmux = tmux;

    g_state = AppState.init(g_allocator);
    loadRecentProjects();
    // Engine and PTY created with real size in bridge_resize (first call)
    return 0;
}

var g_session_name_buf: [64:0]u8 = undefined;

fn startPty(cols: u16, rows: u16) void {
    if (g_engine) |*old| old.deinit();
    g_engine = TerminalEngine.init(g_allocator, cols, rows) catch return;

    // Use current directory name as initial session name
    // When launched from Finder, cwd is "/" — fall back to HOME or "mterm"
    var cwd_buf: [1024]u8 = undefined;
    const cwd = std.posix.getcwd(&cwd_buf) catch "/tmp";
    var dir_name = std.fs.path.basename(cwd);
    if (dir_name.len == 0 or std.mem.eql(u8, dir_name, "/")) {
        // cwd is root — try HOME instead
        const home = std.posix.getenv("HOME") orelse "/tmp";
        dir_name = std.fs.path.basename(home);
        if (dir_name.len == 0 or std.mem.eql(u8, dir_name, "/")) {
            dir_name = "mterm";
        }
        // Also cd to HOME so tmux sessions start there
        std.posix.chdir(home) catch {};
    }
    logFmt("startPty: cwd={s}, session={s}, cols={d}, rows={d}", .{ cwd, dir_name, cols, rows });
    const nlen = @min(dir_name.len, g_session_name_buf.len - 1);
    @memcpy(g_session_name_buf[0..nlen], dir_name[0..nlen]);
    g_session_name_buf[nlen] = 0;

    var pty = Pty.open() catch {
        logMsg("startPty: failed to open PTY");
        return;
    };
    pty.setSize(cols, rows);
    const session_name: [*:0]const u8 = &g_session_name_buf;
    const argv = [_:null]?[*:0]const u8{ "tmux", "new-session", "-A", "-s", session_name, "-e", "CLAUDECODE=" };
    pty.spawn(&argv) catch {
        logMsg("startPty: failed to spawn tmux");
        pty.close();
        return;
    };
    pty.setNonBlocking() catch {};
    g_pty = pty;
    g_started = true;

    syncState();

    // Explicitly select the session we just attached to
    if (g_state) |*state| {
        const target = g_session_name_buf[0..@as(usize, @intCast(std.mem.indexOfScalar(u8, &g_session_name_buf, 0) orelse 0))];
        for (state.sessions.items, 0..) |s, i| {
            if (std.mem.eql(u8, s.name, target)) {
                state.active_session_idx = i;
                break;
            }
        }
    }

    if (g_tmux) |*t| {
        t.hideStatusBar() catch {};
        t.enableMouse();
        // Remove CLAUDECODE from tmux env so nested claude works
        t.clearEnvVar("CLAUDECODE");
    }
    updateRenderCells();
}

fn startPtyAttach(cols: u16, rows: u16) void {
    if (g_engine) |*old| old.deinit();
    g_engine = TerminalEngine.init(g_allocator, cols, rows) catch return;

    var pty = Pty.open() catch return;
    pty.setSize(cols, rows);
    const session_name: [*:0]const u8 = &g_session_name_buf;
    const argv = [_:null]?[*:0]const u8{ "tmux", "attach-session", "-t", session_name };
    pty.spawn(&argv) catch {
        pty.close();
        return;
    };
    pty.setNonBlocking() catch {};
    g_pty = pty;
    g_started = true;

    syncState();

    // Select the attached session
    if (g_state) |*state| {
        const target = g_session_name_buf[0..@as(usize, @intCast(std.mem.indexOfScalar(u8, &g_session_name_buf, 0) orelse 0))];
        for (state.sessions.items, 0..) |s, i| {
            if (std.mem.eql(u8, s.name, target)) {
                state.active_session_idx = i;
                break;
            }
        }
    }

    if (g_tmux) |*t| {
        t.hideStatusBar() catch {};
        t.enableMouse();
        t.clearEnvVar("CLAUDECODE");
    }
    updateRenderCells();
}

export fn bridge_is_started() callconv(.c) u8 {
    return if (g_started) 1 else 0;
}

export fn bridge_start_first_session() callconv(.c) void {
    if (g_started) return;
    startPty(g_initial_cols, g_initial_rows);
}

export fn bridge_tick() callconv(.c) void {
    var pty = &(g_pty orelse return);
    var engine = &(g_engine orelse return);

    // Send any pending responses (e.g. cursor position report)
    if (engine.response_len > 0) {
        _ = pty.write(engine.response_buf[0..engine.response_len]) catch {};
        engine.response_len = 0;
    }

    var poll_fd = [1]posix.pollfd{
        .{ .fd = pty.master_fd, .events = posix.POLL.IN, .revents = 0 },
    };
    _ = posix.poll(&poll_fd, 0) catch {};

    if (poll_fd[0].revents & posix.POLL.IN != 0) {
        var buf: [8192]u8 = undefined;
        const n = pty.read(&buf) catch |err| blk: {
            if (err == error.InputOutput) {
                logMsg("PTY read: InputOutput error, stopping");
                g_running = false;
            }
            break :blk 0;
        };
        if (n > 0) {
            engine.process(buf[0..n]);
            g_redraw = true;
        }
    }

    if (poll_fd[0].revents & posix.POLL.HUP != 0) {
        logMsg("PTY HUP received, attempting reattach");
        reattachOrQuit();
        return;
    }

    // Send responses generated during process()
    if (engine.response_len > 0) {
        _ = pty.write(engine.response_buf[0..engine.response_len]) catch {};
        engine.response_len = 0;
    }

    g_sync_ctr += 1;
    if (g_sync_ctr >= 30) {
        g_sync_ctr = 0;
        syncState();
    }

    if (g_redraw) updateRenderCells();
}

export fn bridge_key_input(data: [*]const u8, len: u32) callconv(.c) void {
    var pty = &(g_pty orelse return);
    const bytes = data[0..len];

    for (bytes) |byte| {
        if (g_leader) {
            g_leader = false;
            if (!handleAppKey(byte)) {
                _ = pty.write(&.{CTRL_A}) catch {};
                _ = pty.write(&.{byte}) catch {};
            }
        } else if (byte == CTRL_A) {
            g_leader = true;
        } else {
            _ = pty.write(&.{byte}) catch {};
        }
    }
}

export fn bridge_resize(cols: u16, rows: u16) callconv(.c) void {
    if (cols == 0 or rows == 0) return;
    if (!g_started) {
        g_initial_cols = cols;
        g_initial_rows = rows;
        if (!g_checked) {
            g_checked = true;
            // Check for existing tmux sessions to attach to
            if (g_tmux) |*tmux| {
                var sessions = tmux.listSessions() catch {
                    g_redraw = true;
                    return;
                };
                if (sessions.items.len > 0) {
                    // Copy first session name before freeing the list
                    const name = sessions.items[0].name;
                    const nlen = @min(name.len, g_session_name_buf.len - 1);
                    @memcpy(g_session_name_buf[0..nlen], name[0..nlen]);
                    g_session_name_buf[nlen] = 0;
                    sessions.clearRetainingCapacity();
                    sessions.deinit(tmux.allocator);
                    startPtyAttach(cols, rows);
                } else {
                    sessions.clearRetainingCapacity();
                    sessions.deinit(tmux.allocator);
                    logMsg("No existing tmux sessions, showing empty state");
                    g_redraw = true;
                }
            }
        }
        return;
    }
    if (g_pty) |*pty| pty.setSize(cols, rows);
    if (g_engine) |*engine| engine.resize(cols, rows) catch {};
    g_redraw = true;
}

export fn bridge_get_cols() callconv(.c) u16 {
    return if (g_engine) |*e| e.screen.cols else 80;
}

export fn bridge_get_rows() callconv(.c) u16 {
    return if (g_engine) |*e| e.screen.rows else 24;
}

export fn bridge_get_cursor_x() callconv(.c) u16 {
    return if (g_engine) |*e| e.screen.cursor_x else 0;
}

export fn bridge_get_cursor_y() callconv(.c) u16 {
    return if (g_engine) |*e| e.screen.cursor_y else 0;
}

export fn bridge_get_cursor_visible() callconv(.c) u8 {
    return if (g_engine) |*e| (if (e.screen.cursor_visible) @as(u8, 1) else 0) else 1;
}

export fn bridge_get_cells() callconv(.c) ?[*]const BridgeCell {
    return if (g_cells) |c| c.ptr else null;
}

export fn bridge_get_cell_count() callconv(.c) u32 {
    return if (g_cells) |c| @intCast(c.len) else 0;
}

export fn bridge_get_session_count() callconv(.c) u16 {
    return if (g_state) |*s| @intCast(s.sessions.items.len) else 0;
}

export fn bridge_get_session_name(idx: u16) callconv(.c) [*]const u8 {
    if (g_state) |*s| {
        if (idx < s.sessions.items.len) return s.sessions.items[idx].name.ptr;
    }
    return "".ptr;
}

export fn bridge_get_session_name_len(idx: u16) callconv(.c) u16 {
    if (g_state) |*s| {
        if (idx < s.sessions.items.len) return @intCast(s.sessions.items[idx].name.len);
    }
    return 0;
}

// --- Display names (auto-computed from active command / path) ---
const MAX_SESSIONS = 32;
const MAX_DISPLAY = 64;
var g_display_bufs: [MAX_SESSIONS][MAX_DISPLAY]u8 = undefined;
var g_display_lens: [MAX_SESSIONS]u16 = [_]u16{0} ** MAX_SESSIONS;

// --- Recent projects ---
const MAX_RECENT = 10;
const MAX_PATH_LEN = 256;
var g_recent_paths: [MAX_RECENT][MAX_PATH_LEN]u8 = undefined;
var g_recent_path_lens: [MAX_RECENT]u16 = [_]u16{0} ** MAX_RECENT;
var g_recent_display: [MAX_RECENT][MAX_DISPLAY]u8 = undefined;
var g_recent_display_lens: [MAX_RECENT]u16 = [_]u16{0} ** MAX_RECENT;
var g_recent_count: u16 = 0;
var g_recent_dirty: bool = false;

export fn bridge_get_session_display_name(idx: u16) callconv(.c) [*]const u8 {
    if (idx < MAX_SESSIONS and g_display_lens[idx] > 0)
        return &g_display_bufs[idx];
    return bridge_get_session_name(idx);
}

export fn bridge_get_session_display_name_len(idx: u16) callconv(.c) u16 {
    if (idx < MAX_SESSIONS and g_display_lens[idx] > 0)
        return g_display_lens[idx];
    return bridge_get_session_name_len(idx);
}

fn updateDisplayNames() void {
    const state = &(g_state orelse return);
    for (state.sessions.items, 0..) |session, i| {
        if (i >= MAX_SESSIONS) break;
        const name = computeDisplayName(&session);
        const len: u16 = @intCast(@min(name.len, MAX_DISPLAY));
        @memcpy(g_display_bufs[i][0..len], name[0..len]);
        g_display_lens[i] = len;
    }
}

fn computeDisplayName(session: *const state_mod.Session) []const u8 {
    // If the user manually renamed the session, always show that name.
    // Auto-generated names match: cwd dirname, dirname-N, session-N, or bare digits.
    if (!isAutoName(session.name)) {
        return session.name;
    }

    const cmd = session.active_command;

    // If running a notable app, show its pretty name
    if (cmd.len > 0 and !isShell(cmd) and !isVersionString(cmd)) {
        if (prettyName(cmd)) |pretty| return pretty;
        return cmd; // unknown app — show raw command name
    }

    // Shell or no command — show session name (preserves the -N suffix)
    return session.name;
}

/// Returns true if the session name looks auto-generated (not user-renamed).
/// Auto names: bare digits ("0", "1"), "session-N", or "<cwd>", "<cwd>-N".
fn isAutoName(name: []const u8) bool {
    if (name.len == 0) return true;

    // Bare digits (tmux default: "0", "1", ...)
    if (allDigits(name)) return true;

    // "session-N"
    if (std.mem.startsWith(u8, name, "session-")) {
        if (allDigits(name["session-".len..])) return true;
    }

    // Match against cwd dirname
    var cwd_buf: [1024]u8 = undefined;
    const cwd = std.posix.getcwd(&cwd_buf) catch return false;
    const dir = std.fs.path.basename(cwd);
    if (dir.len == 0) return false;

    // Exact match: "dirname"
    if (std.mem.eql(u8, name, dir)) return true;

    // "dirname-N"
    if (name.len > dir.len + 1 and
        std.mem.startsWith(u8, name, dir) and
        name[dir.len] == '-' and
        allDigits(name[dir.len + 1 ..]))
    {
        return true;
    }

    return false;
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (c < '0' or c > '9') return false;
    }
    return true;
}

/// Returns true if cmd looks like a version string (e.g. "2.1.74").
/// Some apps (e.g. Claude Code) set their process title to their version,
/// which tmux reports as pane_current_command.
fn isVersionString(cmd: []const u8) bool {
    if (cmd.len == 0) return false;
    var has_dot = false;
    for (cmd) |c| {
        if (c == '.') {
            has_dot = true;
        } else if (c < '0' or c > '9') {
            return false;
        }
    }
    return has_dot;
}

fn isShell(cmd: []const u8) bool {
    const shells = [_][]const u8{ "zsh", "bash", "fish", "sh", "dash", "tcsh", "ksh", "tmux", "login" };
    for (shells) |s| {
        if (std.mem.eql(u8, cmd, s)) return true;
    }
    return false;
}

fn prettyName(cmd: []const u8) ?[]const u8 {
    const Entry = struct { k: []const u8, v: []const u8 };
    const table = [_]Entry{
        .{ .k = "nvim", .v = "NVim" },
        .{ .k = "vim", .v = "Vim" },
        .{ .k = "claude", .v = "Claude Code" },
        .{ .k = "python3", .v = "Python" },
        .{ .k = "python", .v = "Python" },
        .{ .k = "node", .v = "Node.js" },
        .{ .k = "bun", .v = "Bun" },
        .{ .k = "deno", .v = "Deno" },
        .{ .k = "ssh", .v = "SSH" },
        .{ .k = "docker", .v = "Docker" },
        .{ .k = "htop", .v = "htop" },
        .{ .k = "btop", .v = "btop" },
        .{ .k = "top", .v = "top" },
        .{ .k = "less", .v = "less" },
        .{ .k = "man", .v = "man" },
        .{ .k = "cargo", .v = "Cargo" },
        .{ .k = "go", .v = "Go" },
        .{ .k = "zig", .v = "Zig" },
        .{ .k = "make", .v = "Make" },
        .{ .k = "npm", .v = "npm" },
        .{ .k = "yarn", .v = "Yarn" },
        .{ .k = "pnpm", .v = "pnpm" },
        .{ .k = "ruby", .v = "Ruby" },
        .{ .k = "irb", .v = "Ruby IRB" },
        .{ .k = "psql", .v = "PostgreSQL" },
        .{ .k = "mysql", .v = "MySQL" },
        .{ .k = "redis-cli", .v = "Redis" },
        .{ .k = "git", .v = "Git" },
        .{ .k = "lazygit", .v = "LazyGit" },
        .{ .k = "emacs", .v = "Emacs" },
        .{ .k = "nano", .v = "nano" },
        .{ .k = "helix", .v = "Helix" },
        .{ .k = "hx", .v = "Helix" },
        .{ .k = "jupyter", .v = "Jupyter" },
        .{ .k = "ipython", .v = "IPython" },
        .{ .k = "ghci", .v = "GHCi" },
        .{ .k = "lua", .v = "Lua" },
        .{ .k = "swift", .v = "Swift" },
        .{ .k = "kotlinc", .v = "Kotlin" },
        .{ .k = "scala", .v = "Scala" },
        .{ .k = "erl", .v = "Erlang" },
        .{ .k = "iex", .v = "Elixir" },
        .{ .k = "mix", .v = "Elixir Mix" },
    };
    for (table) |e| {
        if (std.mem.eql(u8, cmd, e.k)) return e.v;
    }
    return null;
}

// --- Recent projects FFI ---

export fn bridge_get_recent_project_count() callconv(.c) u16 {
    return g_recent_count;
}

export fn bridge_get_recent_project_display(idx: u16) callconv(.c) [*]const u8 {
    if (idx < g_recent_count and g_recent_display_lens[idx] > 0)
        return &g_recent_display[idx];
    return "".ptr;
}

export fn bridge_get_recent_project_display_len(idx: u16) callconv(.c) u16 {
    if (idx < g_recent_count) return g_recent_display_lens[idx];
    return 0;
}

export fn bridge_get_recent_project_path(idx: u16) callconv(.c) [*]const u8 {
    if (idx < g_recent_count and g_recent_path_lens[idx] > 0)
        return &g_recent_paths[idx];
    return "".ptr;
}

export fn bridge_get_recent_project_path_len(idx: u16) callconv(.c) u16 {
    if (idx < g_recent_count) return g_recent_path_lens[idx];
    return 0;
}

export fn bridge_create_session_in_dir(path_ptr: [*]const u8, path_len: u16) callconv(.c) void {
    const path = path_ptr[0..path_len];
    const dir = std.fs.path.basename(path);
    const tmux = &(g_tmux orelse return);
    const state = &(g_state orelse return);

    if (!g_started) {
        // Set session name from dir and start PTY
        var name = dir;
        if (name.len == 0) name = "mterm";
        const nlen = @min(name.len, g_session_name_buf.len - 1);
        @memcpy(g_session_name_buf[0..nlen], name[0..nlen]);
        g_session_name_buf[nlen] = 0;
        std.posix.chdir(path) catch {};
        startPty(g_initial_cols, g_initial_rows);
        return;
    }

    // Derive unique session name
    var name_buf: [64]u8 = undefined;
    const base = if (dir.len > 0) dir else "mterm";
    const count = state.sessions.items.len;
    const name = if (count == 0)
        std.fmt.bufPrint(&name_buf, "{s}", .{base}) catch return
    else
        std.fmt.bufPrint(&name_buf, "{s}-{d}", .{ base, count }) catch return;

    tmux.createSessionInDir(name, path) catch {};
    syncState();
    g_redraw = true;
}

fn recentProjectsPath() ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/.mterm/recent_projects", .{home}) catch return null;
    return path;
}

fn loadRecentProjects() void {
    const rp_path = recentProjectsPath() orelse return;
    const file = std.fs.cwd().openFile(rp_path, .{}) catch return;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const n = file.readAll(&buf) catch return;
    var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
    g_recent_count = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (g_recent_count >= MAX_RECENT) break;
        const plen: u16 = @intCast(@min(line.len, MAX_PATH_LEN));
        @memcpy(g_recent_paths[g_recent_count][0..plen], line[0..plen]);
        g_recent_path_lens[g_recent_count] = plen;
        // Display name = basename
        const display = std.fs.path.basename(line);
        const dlen: u16 = @intCast(@min(display.len, MAX_DISPLAY));
        @memcpy(g_recent_display[g_recent_count][0..dlen], display[0..dlen]);
        g_recent_display_lens[g_recent_count] = dlen;
        g_recent_count += 1;
    }
}

fn saveRecentProjects() void {
    const rp_path = recentProjectsPath() orelse return;
    // Ensure ~/.mterm/ exists
    const home = std.posix.getenv("HOME") orelse return;
    var dir_buf: [512]u8 = undefined;
    const dir_path = std.fmt.bufPrint(&dir_buf, "{s}/.mterm", .{home}) catch return;
    std.fs.cwd().makeDir(dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return;
    };

    const file = std.fs.cwd().createFile(rp_path, .{ .truncate = true }) catch return;
    defer file.close();
    var i: u16 = 0;
    while (i < g_recent_count) : (i += 1) {
        const plen = g_recent_path_lens[i];
        if (plen > 0) {
            file.writeAll(g_recent_paths[i][0..plen]) catch {};
            file.writeAll("\n") catch {};
        }
    }
}

fn addRecentProject(path: []const u8) void {
    if (path.len == 0) return;
    // Skip root and home itself
    const home = std.posix.getenv("HOME") orelse "";
    if (std.mem.eql(u8, path, "/")) return;
    if (std.mem.eql(u8, path, home)) return;

    // Check for duplicate — if found, move to top
    var i: u16 = 0;
    while (i < g_recent_count) : (i += 1) {
        const existing = g_recent_paths[i][0..g_recent_path_lens[i]];
        if (std.mem.eql(u8, existing, path)) {
            // Move to top by shifting everything down
            if (i > 0) {
                var j = i;
                while (j > 0) : (j -= 1) {
                    g_recent_paths[j] = g_recent_paths[j - 1];
                    g_recent_path_lens[j] = g_recent_path_lens[j - 1];
                    g_recent_display[j] = g_recent_display[j - 1];
                    g_recent_display_lens[j] = g_recent_display_lens[j - 1];
                }
                // Write path to slot 0
                const plen: u16 = @intCast(@min(path.len, MAX_PATH_LEN));
                @memcpy(g_recent_paths[0][0..plen], path[0..plen]);
                g_recent_path_lens[0] = plen;
                const display = std.fs.path.basename(path);
                const dlen: u16 = @intCast(@min(display.len, MAX_DISPLAY));
                @memcpy(g_recent_display[0][0..dlen], display[0..dlen]);
                g_recent_display_lens[0] = dlen;
                g_recent_dirty = true;
            }
            return;
        }
    }

    // Shift everything down, insert at top
    if (g_recent_count < MAX_RECENT) g_recent_count += 1;
    var j: u16 = g_recent_count - 1;
    while (j > 0) : (j -= 1) {
        g_recent_paths[j] = g_recent_paths[j - 1];
        g_recent_path_lens[j] = g_recent_path_lens[j - 1];
        g_recent_display[j] = g_recent_display[j - 1];
        g_recent_display_lens[j] = g_recent_display_lens[j - 1];
    }
    const plen: u16 = @intCast(@min(path.len, MAX_PATH_LEN));
    @memcpy(g_recent_paths[0][0..plen], path[0..plen]);
    g_recent_path_lens[0] = plen;
    const display = std.fs.path.basename(path);
    const dlen: u16 = @intCast(@min(display.len, MAX_DISPLAY));
    @memcpy(g_recent_display[0][0..dlen], display[0..dlen]);
    g_recent_display_lens[0] = dlen;
    g_recent_dirty = true;
}

export fn bridge_is_session_selected(idx: u16) callconv(.c) u8 {
    if (g_state) |*s| {
        return if (s.active_session_idx == idx) 1 else 0;
    }
    return 0;
}

export fn bridge_is_session_attached(idx: u16) callconv(.c) u8 {
    if (g_state) |*s| {
        if (idx < s.sessions.items.len) return if (s.sessions.items[idx].is_attached) @as(u8, 1) else 0;
    }
    return 0;
}

export fn bridge_is_running() callconv(.c) u8 {
    return if (g_running) 1 else 0;
}

export fn bridge_needs_redraw() callconv(.c) u8 {
    return if (g_redraw) 1 else 0;
}

export fn bridge_clear_redraw() callconv(.c) void {
    g_redraw = false;
}

export fn bridge_is_sidebar_visible() callconv(.c) u8 {
    return if (g_state) |*s| (if (s.sidebar_visible) @as(u8, 1) else 0) else 1;
}

export fn bridge_get_sidebar_cols() callconv(.c) u16 {
    return if (g_state) |*s| s.sidebar_width else 30;
}

export fn bridge_select_session(idx: u16) callconv(.c) void {
    var state = &(g_state orelse return);
    const tmux = &(g_tmux orelse return);
    if (idx < state.sessions.items.len) {
        state.active_session_idx = idx;
        if (state.activeSessionName()) |name| tmux.switchSession(name) catch {};
        g_redraw = true;
    }
}

export fn bridge_create_session() callconv(.c) void {
    if (!g_started) {
        // In empty state: start PTY with a new session
        startPty(g_initial_cols, g_initial_rows);
        return;
    }

    const state = &(g_state orelse return);
    const tmux = &(g_tmux orelse return);

    // Use cwd basename + counter for uniqueness
    // When launched from Finder/Spotlight, cwd may be "/" — fall back to HOME
    var cwd_buf: [1024]u8 = undefined;
    const cwd = std.posix.getcwd(&cwd_buf) catch "/tmp";
    var dir = std.fs.path.basename(cwd);
    if (dir.len == 0) {
        const home = std.posix.getenv("HOME") orelse "/tmp";
        dir = std.fs.path.basename(home);
        if (dir.len == 0) dir = "mterm";
    }
    var buf: [64]u8 = undefined;
    const count = state.sessions.items.len;
    const name = if (count == 0)
        std.fmt.bufPrint(&buf, "{s}", .{dir}) catch return
    else
        std.fmt.bufPrint(&buf, "{s}-{d}", .{ dir, count }) catch return;
    tmux.createSession(name) catch {};
    syncState();
    g_redraw = true;
}

export fn bridge_kill_session(idx: u16) callconv(.c) void {
    const state = &(g_state orelse return);
    const tmux = &(g_tmux orelse return);
    if (idx >= state.sessions.items.len) return;

    const is_last = state.sessions.items.len == 1;
    const target_name = state.sessions.items[idx].name;
    logFmt("kill_session: idx={d}, name={s}, is_last={}", .{ idx, target_name, is_last });

    // If this is the last session, just kill it — PTY will HUP and we go to empty state
    if (is_last) {
        tmux.killSession(target_name) catch {};
        // The tmux server exits, PTY gets HUP, reattachOrQuit transitions to empty state
        return;
    } else {
        // Switch to another session BEFORE killing (so our tmux client doesn't exit)
        const other_idx: usize = if (idx == 0) 1 else idx - 1;
        if (other_idx < state.sessions.items.len) {
            tmux.switchSession(state.sessions.items[other_idx].name) catch {};
        }
    }

    // Now safe to kill
    tmux.killSession(target_name) catch {};
    syncState();

    if (state.sessions.items.len > 0) {
        state.active_session_idx = @min(idx, @as(u16, @intCast(state.sessions.items.len -| 1)));
        if (state.activeSessionName()) |n| tmux.switchSession(n) catch {};
    } else {
        state.active_session_idx = null;
    }
    g_redraw = true;
}

export fn bridge_rename_session(idx: u16, new_name: [*]const u8, name_len: u16) callconv(.c) void {
    const state = &(g_state orelse return);
    const tmux = &(g_tmux orelse return);
    if (idx < state.sessions.items.len) {
        const old_name = state.sessions.items[idx].name;
        const new = new_name[0..name_len];
        tmux.renameSession(old_name, new) catch {};
        syncState();
        g_redraw = true;
    }
}

export fn bridge_tmux_command(cmd_id: u8) callconv(.c) void {
    runTmuxCmd(cmd_id);
}

fn runTmuxCmd(cmd_id: u8) void {
    const result = switch (cmd_id) {
        0 => std.process.Child.run(.{ .allocator = g_allocator, .argv = &.{ "tmux", "split-window", "-h" } }),
        1 => std.process.Child.run(.{ .allocator = g_allocator, .argv = &.{ "tmux", "split-window", "-v" } }),
        2 => std.process.Child.run(.{ .allocator = g_allocator, .argv = &.{ "tmux", "new-window" } }),
        3 => std.process.Child.run(.{ .allocator = g_allocator, .argv = &.{ "tmux", "next-window" } }),
        4 => std.process.Child.run(.{ .allocator = g_allocator, .argv = &.{ "tmux", "previous-window" } }),
        5 => std.process.Child.run(.{ .allocator = g_allocator, .argv = &.{ "tmux", "select-pane", "-t", ":.+" } }),
        6 => std.process.Child.run(.{ .allocator = g_allocator, .argv = &.{ "tmux", "kill-pane" } }),
        7 => std.process.Child.run(.{ .allocator = g_allocator, .argv = &.{ "tmux", "resize-pane", "-Z" } }),
        else => return,
    } catch return;
    g_allocator.free(result.stdout);
    g_allocator.free(result.stderr);
    syncState();
    g_redraw = true;
}

export fn bridge_toggle_sidebar() callconv(.c) void {
    var state = &(g_state orelse return);
    state.sidebar_visible = !state.sidebar_visible;
    g_redraw = true;
}

// --- Internal ---

fn reattachOrQuit() void {
    // Close old PTY
    if (g_pty) |*pty| pty.close();
    g_pty = null;

    // Check if tmux has any remaining sessions
    const tmux = &(g_tmux orelse {
        g_running = false;
        return;
    });
    var sessions = tmux.listSessions() catch {
        logMsg("Cannot list sessions, going to empty state");
        g_started = false;
        if (g_state) |*state| {
            state.clearSessions();
            state.active_session_idx = null;
        }
        g_redraw = true;
        return;
    };
    defer {
        sessions.clearRetainingCapacity();
        sessions.deinit(tmux.allocator);
    }

    if (sessions.items.len == 0) {
        logMsg("No tmux sessions remain, going to empty state");
        g_started = false;
        if (g_state) |*state| {
            state.clearSessions();
            state.active_session_idx = null;
        }
        g_redraw = true;
        return;
    }

    // Reattach to the first available session
    const target = sessions.items[0].name;
    logFmt("Reattaching to session: {s}", .{target});

    const engine = &(g_engine orelse return);
    var pty = Pty.open() catch {
        g_running = false;
        return;
    };
    pty.setSize(engine.screen.cols, engine.screen.rows);

    var name_buf: [64:0]u8 = undefined;
    const nlen = @min(target.len, name_buf.len - 1);
    @memcpy(name_buf[0..nlen], target[0..nlen]);
    name_buf[nlen] = 0;
    const sname: [*:0]const u8 = &name_buf;
    const argv = [_:null]?[*:0]const u8{ "tmux", "attach-session", "-t", sname };
    pty.spawn(&argv) catch {
        pty.close();
        g_running = false;
        return;
    };
    pty.setNonBlocking() catch {};
    g_pty = pty;

    syncState();
    g_redraw = true;
}

fn handleAppKey(key: u8) bool {
    var state = &(g_state orelse return false);
    const tmux = &(g_tmux orelse return false);

    switch (key) {
        'q' => {
            g_running = false;
            return true;
        },
        'j' => {
            state.selectNextSession();
            if (state.activeSessionName()) |name| tmux.switchSession(name) catch {};
            g_redraw = true;
            return true;
        },
        'k' => {
            state.selectPrevSession();
            if (state.activeSessionName()) |name| tmux.switchSession(name) catch {};
            g_redraw = true;
            return true;
        },
        'n' => {
            var buf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&buf, "session-{d}", .{state.sessions.items.len}) catch return true;
            tmux.createSession(name) catch {};
            syncState();
            g_redraw = true;
            return true;
        },
        'x' => {
            if (state.active_session_idx) |active_idx| {
                bridge_kill_session(@intCast(active_idx));
            }
            return true;
        },
        'b' => {
            state.sidebar_visible = !state.sidebar_visible;
            g_redraw = true;
            return true;
        },
        CTRL_A => {
            if (g_pty) |*pty| _ = pty.write(&.{CTRL_A}) catch {};
            return true;
        },
        else => return false,
    }
}

fn syncState() void {
    var state = &(g_state orelse return);
    const tmux = &(g_tmux orelse return);

    var saved_buf: [256]u8 = undefined;
    var saved_name: ?[]const u8 = null;
    if (state.activeSessionName()) |n| {
        if (n.len <= saved_buf.len) {
            @memcpy(saved_buf[0..n.len], n);
            saved_name = saved_buf[0..n.len];
        }
    }

    state.clearSessions();
    var sessions = tmux.listSessions() catch return;
    for (sessions.items) |s| {
        state.appendSession(s) catch continue;
    }
    sessions.clearRetainingCapacity();
    sessions.deinit(tmux.allocator);

    var found = false;
    if (saved_name) |name| {
        for (state.sessions.items, 0..) |s, i| {
            if (std.mem.eql(u8, s.name, name)) {
                state.active_session_idx = i;
                found = true;
                break;
            }
        }
    }
    if (!found) {
        for (state.sessions.items, 0..) |s, i| {
            if (s.is_attached) {
                state.active_session_idx = i;
                found = true;
                break;
            }
        }
    }
    if (!found and state.sessions.items.len > 0 and state.active_session_idx == null) {
        state.active_session_idx = 0;
    }
    g_redraw = true;
    updateDisplayNames();

    // Track session paths as recent projects
    for (state.sessions.items) |s| {
        if (s.active_path.len > 0) {
            addRecentProject(s.active_path);
        }
    }
    if (g_recent_dirty) {
        saveRecentProjects();
        g_recent_dirty = false;
    }
}

fn updateRenderCells() void {
    const engine = &(g_engine orelse return);
    const screen = &engine.screen;
    const total = @as(usize, screen.cols) * @as(usize, screen.rows);

    if (g_cells == null or g_cells.?.len != total) {
        if (g_cells) |cells| g_allocator.free(cells);
        g_cells = g_allocator.alloc(BridgeCell, total) catch return;
    }

    var cells = g_cells.?;
    for (screen.cells, 0..) |sc, i| {
        if (i >= cells.len) break;
        cells[i] = .{
            .ch = @intCast(sc.char),
            .fg = colorToU32(sc.fg),
            .bg = colorToU32(sc.bg),
            .attrs = (@as(u8, if (sc.bold) 1 else 0)) |
                (@as(u8, if (sc.underline) 2 else 0)) |
                (@as(u8, if (sc.reverse) 4 else 0)) |
                (@as(u8, if (sc.dim) 8 else 0)) |
                (@as(u8, if (sc.italic) 16 else 0)),
        };
    }
}

fn colorToU32(color: screen_mod.Color) u32 {
    return switch (color) {
        .default => 0xFFFFFFFF,
        .indexed => |idx| indexedToRgb(idx),
        .rgb => |c| (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | c.b,
    };
}

fn indexedToRgb(idx: u8) u32 {
    if (idx < 16) {
        const standard = [16]u32{
            0x262630, 0xCC2626, 0x33BF33, 0xCCBF33,
            0x4066CC, 0xBF40BF, 0x33BFBF, 0xCCCCCC,
            0x737380, 0xFF5959, 0x59FF59, 0xFFFF59,
            0x668CFF, 0xFF66FF, 0x66FFFF, 0xFFFFFF,
        };
        return standard[idx];
    } else if (idx < 232) {
        const ci: u32 = @as(u32, idx) - 16;
        const ri = ci / 36;
        const gi = (ci % 36) / 6;
        const bi = ci % 6;
        const r: u32 = if (ri == 0) 0 else ri * 40 + 55;
        const g: u32 = if (gi == 0) 0 else gi * 40 + 55;
        const b: u32 = if (bi == 0) 0 else bi * 40 + 55;
        return (r << 16) | (g << 8) | b;
    } else {
        const v: u32 = @as(u32, idx - 232) * 10 + 8;
        return (v << 16) | (v << 8) | v;
    }
}
