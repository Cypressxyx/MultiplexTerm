const std = @import("std");
const state_mod = @import("../state.zig");
const TtyWriter = @import("../tty.zig").TtyWriter;

pub const Sidebar = struct {
    width: u16,

    pub fn init(width: u16) Sidebar {
        return .{ .width = width };
    }

    pub fn render(self: *const Sidebar, w: *TtyWriter, app_state: *const state_mod.AppState, term_rows: u16) !void {
        const sw = self.width;

        // Header
        try w.moveTo(1, 1);
        try w.writeAll("\x1b[97;44m"); // white on blue
        try w.writeAll(" MTERM");
        try self.fillTo(w, sw, 6);
        try w.resetSgr();

        // Separator
        try w.moveTo(2, 1);
        try w.writeAll("\x1b[36m"); // cyan
        for (0..sw) |_| try w.writeAll("\xe2\x94\x80"); // ─ (UTF-8)
        try w.resetSgr();

        // Label
        try w.moveTo(3, 1);
        try w.writeAll("\x1b[1;33m"); // bold yellow
        try w.writeAll(" Sessions");
        try self.fillTo(w, sw, 9);
        try w.resetSgr();

        // Session list
        var row: u16 = 4;
        for (app_state.sessions.items, 0..) |session, i| {
            if (row >= term_rows - 1) break;

            try w.moveTo(row, 1);

            const is_selected = app_state.active_session_idx == i;
            const is_attached = session.is_attached;

            if (is_selected) {
                try w.writeAll("\x1b[1;97;42m"); // bold white on green
            } else if (is_attached) {
                try w.writeAll("\x1b[1;36m"); // bold cyan
            } else {
                try w.writeAll("\x1b[37m"); // white
            }

            // Indicator + name
            if (is_selected) {
                try w.writeAll(" \xe2\x96\xb6 "); // ▶
            } else if (is_attached) {
                try w.writeAll(" \xe2\x97\x8f "); // ●
            } else {
                try w.writeAll("   ");
            }

            const max_name: usize = @as(usize, sw) -| 5;
            const name = session.name;
            const display_len = @min(name.len, max_name);
            try w.writeAll(name[0..display_len]);
            try self.fillTo(w, sw, @intCast(3 + display_len));
            try w.resetSgr();

            row += 1;
        }

        // Fill empty rows
        while (row < term_rows - 1) : (row += 1) {
            try w.moveTo(row, 1);
            try self.fillTo(w, sw, 0);
        }

        // Help bar
        try w.moveTo(term_rows - 1, 1);
        try w.writeAll("\x1b[90m"); // dark gray
        try w.writeAll(" ^A-n:new ^A-x:del");
        try self.fillTo(w, sw, 18);
        try w.resetSgr();

        // Status bar
        try w.moveTo(term_rows, 1);
        try w.writeAll("\x1b[97;44m");
        if (app_state.activeSessionName()) |name| {
            try w.writeAll(" ");
            const max_len: usize = @as(usize, sw) -| 2;
            const dl = @min(name.len, max_len);
            try w.writeAll(name[0..dl]);
            try self.fillTo(w, sw, @intCast(1 + dl));
        } else {
            try w.writeAll(" No session");
            try self.fillTo(w, sw, 11);
        }
        try w.resetSgr();

        // Vertical separator
        for (1..@as(usize, term_rows) + 1) |r| {
            try w.moveTo(@intCast(r), sw + 1);
            try w.writeAll("\x1b[36m\xe2\x94\x82\x1b[0m"); // │ in cyan
        }
    }

    fn fillTo(_: *const Sidebar, w: *TtyWriter, target: u16, used: u16) !void {
        var remaining: u16 = target -| used;
        while (remaining > 0) : (remaining -= 1) {
            try w.writeByte(' ');
        }
    }
};
