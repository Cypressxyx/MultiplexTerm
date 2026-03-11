const std = @import("std");

pub const Session = struct {
    id: []const u8,
    name: []const u8,
    is_attached: bool = false,
    is_active: bool = false,
    window_count: u16 = 0,
    active_command: []const u8 = "",
    active_path: []const u8 = "",
};

pub const Window = struct {
    id: []const u8,
    index: u16 = 0,
    name: []const u8,
    is_active: bool = false,
};

pub const Pane = struct {
    id: []const u8,
    title: []const u8,
    cwd: []const u8,
    command: []const u8,
    is_active: bool = false,
};

const SessionList = std.ArrayList(Session);

pub const AppState = struct {
    sessions: SessionList = .empty,
    active_session_idx: ?usize = null,
    sidebar_visible: bool = true,
    sidebar_width: u16 = 30,
    needs_redraw: bool = true,
    running: bool = true,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AppState {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AppState) void {
        self.clearSessions();
        self.sessions.deinit(self.allocator);
    }

    pub fn clearSessions(self: *AppState) void {
        for (self.sessions.items) |s| {
            self.allocator.free(s.id);
            self.allocator.free(s.name);
            if (s.active_command.len > 0) self.allocator.free(s.active_command);
            if (s.active_path.len > 0) self.allocator.free(s.active_path);
        }
        self.sessions.clearRetainingCapacity();
    }

    pub fn activeSessionName(self: *const AppState) ?[]const u8 {
        if (self.active_session_idx) |idx| {
            if (idx < self.sessions.items.len) {
                return self.sessions.items[idx].name;
            }
        }
        return null;
    }

    pub fn selectNextSession(self: *AppState) void {
        if (self.sessions.items.len == 0) return;
        if (self.active_session_idx) |idx| {
            self.active_session_idx = (idx + 1) % self.sessions.items.len;
        } else {
            self.active_session_idx = 0;
        }
        self.needs_redraw = true;
    }

    pub fn selectPrevSession(self: *AppState) void {
        if (self.sessions.items.len == 0) return;
        if (self.active_session_idx) |idx| {
            self.active_session_idx = if (idx == 0) self.sessions.items.len - 1 else idx - 1;
        } else {
            self.active_session_idx = 0;
        }
        self.needs_redraw = true;
    }

    pub fn appendSession(self: *AppState, session: Session) !void {
        try self.sessions.append(self.allocator, session);
    }
};
