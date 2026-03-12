const std = @import("std");
const state_mod = @import("../state.zig");

const SessionList = std.ArrayList(state_mod.Session);
const WindowList = std.ArrayList(state_mod.Window);
const PaneList = std.ArrayList(state_mod.Pane);

pub const TmuxManager = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TmuxManager {
        return .{ .allocator = allocator };
    }

    pub fn isAvailable(self: *const TmuxManager) bool {
        _ = self;
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &.{ "tmux", "-V" },
        }) catch return false;
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
        return result.term.Exited == 0;
    }

    pub fn listSessions(self: *const TmuxManager) !SessionList {
        var sessions: SessionList = .empty;

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{
                "tmux", "list-sessions", "-F",
                "#{session_id}|#{session_name}|#{session_attached}|#{session_windows}|#{session_activity}|#{pane_current_command}|#{pane_current_path}|#{session_created}",
            },
        }) catch return sessions;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return sessions;

        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const session = parseSessionLine(self.allocator, line) catch continue;
            sessions.append(self.allocator, session) catch continue;
        }

        // Sort by creation time (newest first) so new sessions appear at the top
        std.mem.sortUnstable(state_mod.Session, sessions.items, {}, struct {
            fn lessThan(_: void, a: state_mod.Session, b: state_mod.Session) bool {
                return a.created > b.created;
            }
        }.lessThan);

        return sessions;
    }

    pub fn listWindows(self: *const TmuxManager, session_name: []const u8) !WindowList {
        var windows: WindowList = .empty;

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{
                "tmux", "list-windows", "-t", session_name, "-F",
                "#{window_id}|#{window_index}|#{window_name}|#{window_active}|#{window_panes}",
            },
        }) catch return windows;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return windows;

        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const window = parseWindowLine(self.allocator, line) catch continue;
            windows.append(self.allocator, window) catch continue;
        }

        return windows;
    }

    pub fn listPanes(self: *const TmuxManager, target: []const u8) !PaneList {
        var panes: PaneList = .empty;

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{
                "tmux", "list-panes", "-t", target, "-F",
                "#{pane_id}|#{pane_title}|#{pane_current_path}|#{pane_current_command}|#{pane_active}",
            },
        }) catch return panes;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return panes;

        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const pane = parsePaneLine(self.allocator, line) catch continue;
            panes.append(self.allocator, pane) catch continue;
        }

        return panes;
    }

    pub fn switchSession(self: *const TmuxManager, session_name: []const u8) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "switch-client", "-t", session_name },
        }) catch return error.TmuxCommandFailed;
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return error.TmuxCommandFailed;
    }

    pub fn createSession(self: *const TmuxManager, name: []const u8) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "new-session", "-d", "-s", name, "-e", "CLAUDECODE=" },
        }) catch return error.TmuxCommandFailed;
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return error.TmuxCommandFailed;
    }

    pub fn createSessionInDir(self: *const TmuxManager, name: []const u8, dir: []const u8) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "new-session", "-d", "-s", name, "-c", dir, "-e", "CLAUDECODE=" },
        }) catch return error.TmuxCommandFailed;
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return error.TmuxCommandFailed;
    }

    /// Create a local tmux session that runs an SSH command to attach to a remote tmux session.
    /// The local session name is "ssh:<host>/<remote_session>".
    pub fn createSshSession(self: *const TmuxManager, session_name: []const u8, ssh_host: []const u8, remote_session: []const u8) !void {
        // Build: ssh HOST -t 'tmux attach-session -t SESSION'
        var cmd_buf: [512]u8 = undefined;
        const ssh_cmd = std.fmt.bufPrint(&cmd_buf, "tmux attach-session -t '{s}'", .{remote_session}) catch return error.TmuxCommandFailed;

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "new-session", "-d", "-s", session_name, "-e", "CLAUDECODE=", "ssh", ssh_host, "-t", ssh_cmd },
        }) catch return error.TmuxCommandFailed;
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return error.TmuxCommandFailed;
    }

    pub fn renameSession(self: *const TmuxManager, old_name: []const u8, new_name: []const u8) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "rename-session", "-t", old_name, new_name },
        }) catch return error.TmuxCommandFailed;
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return error.TmuxCommandFailed;
    }

    pub fn killSession(self: *const TmuxManager, name: []const u8) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "kill-session", "-t", name },
        }) catch return error.TmuxCommandFailed;
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);

        if (result.term.Exited != 0) return error.TmuxCommandFailed;
    }

    pub fn hideStatusBar(self: *const TmuxManager) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "set-option", "-g", "status", "off" },
        }) catch return error.TmuxCommandFailed;
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);
    }

    pub fn enableMouse(self: *const TmuxManager) void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "set-option", "-g", "mouse", "on" },
        }) catch return;
        self.allocator.free(result.stdout);
        self.allocator.free(result.stderr);
    }

    pub fn clearEnvVar(self: *const TmuxManager, name: []const u8) void {
        // Unset from global tmux environment (affects new panes/windows)
        const r1 = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{ "tmux", "set-environment", "-g", "-u", name },
        }) catch return;
        self.allocator.free(r1.stdout);
        self.allocator.free(r1.stderr);
    }

    // --- Parsers ---

    fn parseSessionLine(allocator: std.mem.Allocator, line: []const u8) !state_mod.Session {
        var fields = std.mem.splitScalar(u8, line, '|');
        const id = fields.next() orelse return error.ParseError;
        const name = fields.next() orelse return error.ParseError;
        const attached_str = fields.next() orelse return error.ParseError;
        const windows_str = fields.next() orelse return error.ParseError;
        _ = fields.next(); // activity (unused)
        const command = fields.next() orelse "";
        const path = fields.next() orelse "";
        const created_str = fields.next() orelse "0";

        return .{
            .id = try allocator.dupe(u8, id),
            .name = try allocator.dupe(u8, name),
            .is_attached = std.mem.eql(u8, attached_str, "1"),
            .window_count = std.fmt.parseInt(u16, windows_str, 10) catch 0,
            .active_command = if (command.len > 0) try allocator.dupe(u8, command) else "",
            .active_path = if (path.len > 0) try allocator.dupe(u8, path) else "",
            .created = std.fmt.parseInt(i64, created_str, 10) catch 0,
        };
    }

    fn parseWindowLine(allocator: std.mem.Allocator, line: []const u8) !state_mod.Window {
        var fields = std.mem.splitScalar(u8, line, '|');
        const id = fields.next() orelse return error.ParseError;
        const index_str = fields.next() orelse return error.ParseError;
        const name = fields.next() orelse return error.ParseError;
        const active_str = fields.next() orelse return error.ParseError;

        return .{
            .id = try allocator.dupe(u8, id),
            .index = std.fmt.parseInt(u16, index_str, 10) catch 0,
            .name = try allocator.dupe(u8, name),
            .is_active = std.mem.eql(u8, active_str, "1"),
        };
    }

    fn parsePaneLine(allocator: std.mem.Allocator, line: []const u8) !state_mod.Pane {
        var fields = std.mem.splitScalar(u8, line, '|');
        const id = fields.next() orelse return error.ParseError;
        const title = fields.next() orelse return error.ParseError;
        const cwd = fields.next() orelse return error.ParseError;
        const command = fields.next() orelse return error.ParseError;
        const active_str = fields.next() orelse return error.ParseError;

        return .{
            .id = try allocator.dupe(u8, id),
            .title = try allocator.dupe(u8, title),
            .cwd = try allocator.dupe(u8, cwd),
            .command = try allocator.dupe(u8, command),
            .is_active = std.mem.eql(u8, active_str, "1"),
        };
    }
};
