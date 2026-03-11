const std = @import("std");
const state_mod = @import("../state.zig");
const TtyWriter = @import("../tty.zig").TtyWriter;

pub const TopBar = struct {
    pub fn render(w: *TtyWriter, app_state: *const state_mod.AppState, term_cols: u16) !void {
        const sidebar_w: u16 = if (app_state.sidebar_visible) app_state.sidebar_width + 2 else 1;
        if (sidebar_w >= term_cols) return;

        try w.moveTo(1, sidebar_w);
        try w.writeAll("\x1b[97;44m"); // white on blue

        try w.writeAll(" mterm");
        var used: u16 = sidebar_w + 6;

        if (app_state.activeSessionName()) |name| {
            try w.writeAll(" | ");
            const max_len = @min(name.len, @as(usize, term_cols -| used -| 5));
            try w.writeAll(name[0..max_len]);
            used += @intCast(3 + max_len);
        }

        // Fill remaining
        while (used < term_cols) : (used += 1) {
            try w.writeByte(' ');
        }

        try w.resetSgr();
    }
};
