const std = @import("std");
const state_mod = @import("state.zig");

/// Integration tests for mterm using isolated tmux instances.
/// Each test gets its own tmux socket (-L) and TMUX_TMPDIR to avoid
/// interfering with the user's real tmux sessions.

const TestTmux = struct {
    socket: []const u8,
    tmpdir: []const u8,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, name: []const u8) !TestTmux {
        // Create isolated tmpdir
        var path_buf: [256]u8 = undefined;
        const tmpdir = std.fmt.bufPrint(&path_buf, "/tmp/mterm-test-{s}", .{name}) catch return error.BufferTooSmall;
        const owned_tmpdir = try allocator.dupe(u8, tmpdir);

        std.fs.makeDirAbsolute(owned_tmpdir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };

        const owned_socket = try allocator.dupe(u8, name);
        return .{
            .socket = owned_socket,
            .tmpdir = owned_tmpdir,
            .allocator = allocator,
        };
    }

    fn deinit(self: *TestTmux) void {
        // Kill the test tmux server
        if (self.run(&.{ "tmux", "-L", self.socket, "kill-server" })) |out| {
            self.allocator.free(out);
        } else |_| {}
        // Remove tmpdir
        std.fs.deleteTreeAbsolute(self.tmpdir) catch {};
        self.allocator.free(self.socket);
        self.allocator.free(self.tmpdir);
    }

    fn run(self: *const TestTmux, argv: []const []const u8) ![]u8 {
        var env_map = std.process.EnvMap.init(self.allocator);
        defer env_map.deinit();

        // Inherit minimal env
        if (std.posix.getenv("PATH")) |p| try env_map.put("PATH", p);
        if (std.posix.getenv("HOME")) |h| try env_map.put("HOME", h);
        try env_map.put("TMUX_TMPDIR", self.tmpdir);

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv,
            .env_map = &env_map,
        });
        self.allocator.free(result.stderr);
        if (result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            return error.TmuxCommandFailed;
        }
        return result.stdout;
    }

    fn newSession(self: *const TestTmux, name: []const u8) !void {
        const stdout = try self.run(&.{ "tmux", "-L", self.socket, "new-session", "-d", "-s", name });
        self.allocator.free(stdout);
    }

    fn newSessionInDir(self: *const TestTmux, name: []const u8, dir: []const u8) !void {
        const stdout = try self.run(&.{ "tmux", "-L", self.socket, "new-session", "-d", "-s", name, "-c", dir });
        self.allocator.free(stdout);
    }

    fn killSession(self: *const TestTmux, name: []const u8) !void {
        const stdout = try self.run(&.{ "tmux", "-L", self.socket, "kill-session", "-t", name });
        self.allocator.free(stdout);
    }

    fn listSessionNames(self: *const TestTmux) !std.ArrayList([]u8) {
        var names: std.ArrayList([]u8) = .empty;
        const stdout = self.run(&.{
            "tmux", "-L", self.socket, "list-sessions", "-F", "#{session_name}",
        }) catch |e| switch (e) {
            error.TmuxCommandFailed => return names, // no sessions = no server
            else => return e,
        };
        defer self.allocator.free(stdout);

        var lines = std.mem.splitScalar(u8, stdout, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const name = try self.allocator.dupe(u8, line);
            try names.append(self.allocator, name);
        }
        return names;
    }

    fn freeNameList(self: *const TestTmux, list: *std.ArrayList([]u8)) void {
        for (list.items) |name| self.allocator.free(name);
        list.deinit(self.allocator);
    }

    fn renameSession(self: *const TestTmux, old: []const u8, new: []const u8) !void {
        const stdout = try self.run(&.{ "tmux", "-L", self.socket, "rename-session", "-t", old, new });
        self.allocator.free(stdout);
    }

    fn getPaneCommand(self: *const TestTmux, session: []const u8) ![]u8 {
        return self.run(&.{
            "tmux", "-L", self.socket, "list-panes", "-t", session, "-F", "#{pane_current_command}",
        });
    }

    fn getPanePath(self: *const TestTmux, session: []const u8) ![]u8 {
        return self.run(&.{
            "tmux", "-L", self.socket, "list-panes", "-t", session, "-F", "#{pane_current_path}",
        });
    }
};

// ─── Tmux Integration Tests ────────────────────────────────────────

test "tmux session lifecycle: create, list, kill" {
    const alloc = std.testing.allocator;
    var tmux = try TestTmux.init(alloc, "lifecycle");
    defer tmux.deinit();

    // Start with no sessions
    var names = try tmux.listSessionNames();
    try std.testing.expectEqual(@as(usize, 0), names.items.len);
    tmux.freeNameList(&names);

    // Create two sessions
    try tmux.newSession("alpha");
    try tmux.newSession("beta");

    // Verify both exist
    names = try tmux.listSessionNames();
    try std.testing.expectEqual(@as(usize, 2), names.items.len);

    var found_alpha = false;
    var found_beta = false;
    for (names.items) |name| {
        if (std.mem.eql(u8, name, "alpha")) found_alpha = true;
        if (std.mem.eql(u8, name, "beta")) found_beta = true;
    }
    try std.testing.expect(found_alpha);
    try std.testing.expect(found_beta);
    tmux.freeNameList(&names);

    // Kill one
    try tmux.killSession("alpha");
    names = try tmux.listSessionNames();
    try std.testing.expectEqual(@as(usize, 1), names.items.len);
    try std.testing.expectEqualStrings("beta", names.items[0]);
    tmux.freeNameList(&names);

    // Kill the last one
    try tmux.killSession("beta");
    names = try tmux.listSessionNames();
    try std.testing.expectEqual(@as(usize, 0), names.items.len);
    tmux.freeNameList(&names);
}

test "tmux session rename" {
    const alloc = std.testing.allocator;
    var tmux = try TestTmux.init(alloc, "rename");
    defer tmux.deinit();

    try tmux.newSession("original");
    try tmux.renameSession("original", "renamed");

    var names = try tmux.listSessionNames();
    try std.testing.expectEqual(@as(usize, 1), names.items.len);
    try std.testing.expectEqualStrings("renamed", names.items[0]);
    tmux.freeNameList(&names);
}

test "tmux session in directory" {
    const alloc = std.testing.allocator;
    var tmux = try TestTmux.init(alloc, "dir");
    defer tmux.deinit();

    try tmux.newSessionInDir("dirtest", "/tmp");

    const path_raw = try tmux.getPanePath("dirtest");
    defer alloc.free(path_raw);
    const path = std.mem.trimRight(u8, path_raw, "\n");

    // On macOS, /tmp → /private/tmp
    try std.testing.expect(
        std.mem.eql(u8, path, "/tmp") or std.mem.eql(u8, path, "/private/tmp"),
    );
}

test "tmux duplicate session name fails" {
    const alloc = std.testing.allocator;
    var tmux = try TestTmux.init(alloc, "dup");
    defer tmux.deinit();

    try tmux.newSession("unique");
    // Creating a session with the same name should fail
    const result = tmux.newSession("unique");
    try std.testing.expectError(error.TmuxCommandFailed, result);
}

test "tmux session runs a shell" {
    const alloc = std.testing.allocator;
    var tmux = try TestTmux.init(alloc, "shell");
    defer tmux.deinit();

    try tmux.newSession("shelltest");

    const cmd_raw = try tmux.getPaneCommand("shelltest");
    defer alloc.free(cmd_raw);
    const cmd = std.mem.trimRight(u8, cmd_raw, "\n");

    // Default pane should be running a shell (zsh, bash, etc.)
    const shells = [_][]const u8{ "zsh", "bash", "fish", "sh", "dash", "tcsh", "ksh", "login" };
    var is_shell = false;
    for (shells) |s| {
        if (std.mem.eql(u8, cmd, s)) {
            is_shell = true;
            break;
        }
    }
    try std.testing.expect(is_shell);
}

// ─── SSH host file persistence tests ────────────────────────────────

test "SSH host file round-trip" {
    const test_path = "/tmp/mterm-test-ssh-hosts";

    // Clean up any existing file
    std.fs.deleteFileAbsolute(test_path) catch {};
    defer std.fs.deleteFileAbsolute(test_path) catch {};

    // Write hosts
    {
        const f = try std.fs.createFileAbsolute(test_path, .{});
        defer f.close();
        try f.writeAll("server1.example.com\nserver2.local\nmy-host\n");
    }

    // Read back and verify
    const contents = try std.fs.openFileAbsolute(test_path, .{});
    defer contents.close();
    var buf: [1024]u8 = undefined;
    const len = try contents.readAll(&buf);
    const data = buf[0..len];

    var lines = std.mem.splitScalar(u8, data, '\n');
    var count: usize = 0;
    var found = [3]bool{ false, false, false };
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "server1.example.com")) found[0] = true;
        if (std.mem.eql(u8, line, "server2.local")) found[1] = true;
        if (std.mem.eql(u8, line, "my-host")) found[2] = true;
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expect(found[0] and found[1] and found[2]);
}

// ─── Terminal engine tests ──────────────────────────────────────────

test "terminal engine processes plain text" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    const alloc = std.testing.allocator;

    var engine = try TerminalEngine.init(alloc, 80, 24);
    defer engine.deinit();

    engine.process("Hello, World!");

    // Check that the text was written to the screen
    const screen = &engine.screen;
    const cols = screen.cols;

    // 'H' should be at column 0, row 0
    try std.testing.expectEqual(@as(u21, 'H'), screen.cells[0].char);
    try std.testing.expectEqual(@as(u21, 'e'), screen.cells[1].char);
    try std.testing.expectEqual(@as(u21, 'l'), screen.cells[2].char);
    try std.testing.expectEqual(@as(u21, 'o'), screen.cells[4].char);

    // Cursor should be at column 13 (after "Hello, World!")
    try std.testing.expectEqual(@as(u16, 13), screen.cursor_x);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_y);

    _ = cols;
}

test "terminal engine handles newline" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    const alloc = std.testing.allocator;

    var engine = try TerminalEngine.init(alloc, 80, 24);
    defer engine.deinit();

    engine.process("line1\r\nline2");

    const screen = &engine.screen;
    const cols: usize = screen.cols;

    // First line: 'l' at (0,0)
    try std.testing.expectEqual(@as(u21, 'l'), screen.cells[0].char);
    try std.testing.expectEqual(@as(u21, 'i'), screen.cells[1].char);
    // Second line: 'l' at (0,1)
    try std.testing.expectEqual(@as(u21, 'l'), screen.cells[cols].char);
    try std.testing.expectEqual(@as(u21, 'i'), screen.cells[cols + 1].char);
}

test "terminal engine handles cursor movement CSI" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    const alloc = std.testing.allocator;

    var engine = try TerminalEngine.init(alloc, 80, 24);
    defer engine.deinit();

    // Write "AB", then cursor back 1, write "X" → overwrites B with X
    engine.process("AB\x1b[1DX");

    const screen = &engine.screen;
    try std.testing.expectEqual(@as(u21, 'A'), screen.cells[0].char);
    try std.testing.expectEqual(@as(u21, 'X'), screen.cells[1].char);
}

test "terminal engine SGR bold and color" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    const screen_mod = @import("terminal/screen.zig");
    const alloc = std.testing.allocator;

    var engine = try TerminalEngine.init(alloc, 80, 24);
    defer engine.deinit();

    // ESC[1;31m = bold + red foreground
    engine.process("\x1b[1;31mR");

    const screen = &engine.screen;
    const cell = screen.cells[0];
    try std.testing.expectEqual(@as(u21, 'R'), cell.char);
    try std.testing.expect(cell.bold);
    try std.testing.expectEqual(screen_mod.Color{ .indexed = 1 }, cell.fg);
}

test "terminal engine alt screen switch" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    const alloc = std.testing.allocator;

    var engine = try TerminalEngine.init(alloc, 80, 24);
    defer engine.deinit();

    // Write on main screen
    engine.process("main");

    // Switch to alt screen (DEC 1049)
    engine.process("\x1b[?1049h");
    engine.process("alt");

    const screen = &engine.screen;
    try std.testing.expectEqual(@as(u21, 'a'), screen.cells[0].char);

    // Switch back to main screen
    engine.process("\x1b[?1049l");
    try std.testing.expectEqual(@as(u21, 'm'), screen.cells[0].char);
}

test "terminal engine erase display" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    const alloc = std.testing.allocator;

    var engine = try TerminalEngine.init(alloc, 80, 24);
    defer engine.deinit();

    engine.process("Hello");
    // ESC[2J = erase entire display
    engine.process("\x1b[2J");

    const screen = &engine.screen;
    // All cells should be spaces
    try std.testing.expectEqual(@as(u21, ' '), screen.cells[0].char);
    try std.testing.expectEqual(@as(u21, ' '), screen.cells[1].char);
}

test "terminal engine scroll region" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    const alloc = std.testing.allocator;

    var engine = try TerminalEngine.init(alloc, 80, 5);
    defer engine.deinit();

    // Set scroll region to rows 2-4 (1-indexed in CSI: ESC[2;4r)
    engine.process("\x1b[2;4r");

    try std.testing.expectEqual(@as(u16, 1), engine.screen.scroll_top);
    try std.testing.expectEqual(@as(u16, 3), engine.screen.scroll_bottom);
}

test "terminal engine wrap at edge" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    const alloc = std.testing.allocator;

    var engine = try TerminalEngine.init(alloc, 5, 3);
    defer engine.deinit();

    // Write exactly 5 chars to fill row 0, then one more to wrap to row 1
    engine.process("ABCDEF");

    const screen = &engine.screen;
    const cols: usize = screen.cols;
    try std.testing.expectEqual(@as(u21, 'A'), screen.cells[0].char);
    try std.testing.expectEqual(@as(u21, 'E'), screen.cells[4].char);
    try std.testing.expectEqual(@as(u21, 'F'), screen.cells[cols].char);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_y);
}
