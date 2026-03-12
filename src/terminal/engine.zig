const std = @import("std");
const VtParser = @import("parser.zig").VtParser;
const Screen = @import("screen.zig").Screen;

pub const TerminalEngine = struct {
    parser: VtParser = .{},
    screen: Screen,
    response_buf: [64]u8 = undefined,
    response_len: u8 = 0,

    const EventHandler = struct {
        engine: *TerminalEngine,

        pub fn onEvent(self: *const EventHandler, event: VtParser.Event) void {
            const screen = &self.engine.screen;
            switch (event) {
                .print => |ch| screen.putChar(ch),
                .newline => screen.linefeed(),
                .carriage_return => screen.carriageReturn(),
                .backspace => screen.backspace(),
                .tab => screen.tab(),
                .bell => {},
                .save_cursor => screen.saveCursor(),
                .restore_cursor => screen.restoreCursor(),
                .reverse_index => screen.reverseIndex(),
                .index => screen.linefeed(),
                .reset => {
                    screen.eraseDisplay(2);
                    screen.setCursorPos(0, 0);
                    screen.current_attr = .{};
                    screen.scroll_top = 0;
                    screen.scroll_bottom = screen.rows -| 1;
                    screen.auto_wrap = true;
                    screen.cursor_visible = true;
                    screen.charset_g0 = .ascii;
                    screen.charset_g1 = .ascii;
                    screen.active_charset = .g0;
                },
                .csi => |csi| self.engine.handleCsi(csi),
                .execute => {},
                .osc => {},
                .charset_g0 => |ch| {
                    screen.charset_g0 = if (ch == '0') .line_drawing else .ascii;
                },
                .charset_g1 => |ch| {
                    screen.charset_g1 = if (ch == '0') .line_drawing else .ascii;
                },
                .shift_out => {
                    screen.active_charset = .g1;
                },
                .shift_in => {
                    screen.active_charset = .g0;
                },
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, cols: u16, rows: u16) !TerminalEngine {
        return .{ .screen = try Screen.init(allocator, cols, rows) };
    }

    pub fn deinit(self: *TerminalEngine) void {
        self.screen.deinit();
    }

    pub fn process(self: *TerminalEngine, data: []const u8) void {
        const handler = EventHandler{ .engine = self };
        for (data) |byte| {
            self.parser.feed(byte, &handler);
        }
    }

    pub fn resize(self: *TerminalEngine, cols: u16, rows: u16) !void {
        try self.screen.resize(cols, rows);
    }

    fn paramOr(params: []const u16, idx: usize, default: u16) u16 {
        return if (idx < params.len and params[idx] > 0) params[idx] else default;
    }

    fn handleCsi(self: *TerminalEngine, csi: VtParser.CsiEvent) void {
        const screen = &self.screen;
        const p = csi.params;

        if (csi.private_marker == '?') {
            self.handleDecPrivateMode(csi);
            return;
        }

        switch (csi.final) {
            'A' => { // Cursor Up
                screen.cursor_y -|= paramOr(p, 0, 1);
                screen.wrap_next = false;
            },
            'B' => { // Cursor Down
                screen.cursor_y = @min(screen.cursor_y +| paramOr(p, 0, 1), screen.rows -| 1);
                screen.wrap_next = false;
            },
            'C' => { // Cursor Forward
                screen.cursor_x = @min(screen.cursor_x +| paramOr(p, 0, 1), screen.cols -| 1);
                screen.wrap_next = false;
            },
            'D' => { // Cursor Back
                screen.cursor_x -|= paramOr(p, 0, 1);
                screen.wrap_next = false;
            },
            'E' => { // Cursor Next Line
                screen.cursor_y = @min(screen.cursor_y +| paramOr(p, 0, 1), screen.rows -| 1);
                screen.cursor_x = 0;
                screen.wrap_next = false;
            },
            'F' => { // Cursor Previous Line
                screen.cursor_y -|= paramOr(p, 0, 1);
                screen.cursor_x = 0;
                screen.wrap_next = false;
            },
            'G' => { // Cursor Horizontal Absolute
                screen.cursor_x = @min(paramOr(p, 0, 1) -| 1, screen.cols -| 1);
                screen.wrap_next = false;
            },
            'H', 'f' => { // Cursor Position
                const row = paramOr(p, 0, 1) -| 1;
                const col = paramOr(p, 1, 1) -| 1;
                screen.setCursorPos(row, col);
            },
            'J' => screen.eraseDisplay(if (p.len > 0) p[0] else 0),
            'K' => screen.eraseLine(if (p.len > 0) p[0] else 0),
            'L' => screen.insertLines(paramOr(p, 0, 1)),
            'M' => screen.deleteLines(paramOr(p, 0, 1)),
            '@' => screen.insertChars(paramOr(p, 0, 1)),
            'P' => screen.deleteChars(paramOr(p, 0, 1)),
            'X' => screen.eraseChars(paramOr(p, 0, 1)),
            'S' => screen.scrollUpRegion(paramOr(p, 0, 1)),
            'T' => screen.scrollDownRegion(paramOr(p, 0, 1)),
            'd' => { // Vertical Position Absolute
                screen.cursor_y = @min(paramOr(p, 0, 1) -| 1, screen.rows -| 1);
                screen.wrap_next = false;
            },
            'm' => screen.handleSgr(p),
            'r' => { // Set Scroll Region
                const top = paramOr(p, 0, 1) -| 1;
                const bot = if (p.len > 1 and p[1] > 0) p[1] -| 1 else screen.rows -| 1;
                screen.setScrollRegion(top, bot);
            },
            'h' => {}, // SM (non-private) — ignore
            'l' => {}, // RM (non-private) — ignore
            's' => screen.saveCursor(),
            'u' => screen.restoreCursor(),
            'n' => { // Device Status Report
                if (p.len > 0 and p[0] == 6) {
                    const row = screen.cursor_y + 1;
                    const col = screen.cursor_x + 1;
                    const resp = std.fmt.bufPrint(&self.response_buf, "\x1b[{d};{d}R", .{ row, col }) catch return;
                    self.response_len = @intCast(resp.len);
                }
            },
            'c' => { // Device Attributes
                if (csi.private_marker == 0 and (p.len == 0 or p[0] == 0)) {
                    const resp = "\x1b[?1;2c";
                    @memcpy(self.response_buf[0..resp.len], resp);
                    self.response_len = resp.len;
                }
            },
            't' => {}, // Window manipulation — ignore
            else => {},
        }
    }

    fn handleDecPrivateMode(self: *TerminalEngine, csi: VtParser.CsiEvent) void {
        if (csi.final != 'h' and csi.final != 'l') return;
        const screen = &self.screen;
        const set = csi.final == 'h';

        for (csi.params) |mode| {
            switch (mode) {
                1 => {}, // DECCKM — application cursor keys
                7 => screen.auto_wrap = set,
                12 => {}, // Blinking cursor
                25 => screen.cursor_visible = set,
                1049 => {
                    if (set) {
                        screen.saveCursor();
                        screen.enterAltScreen();
                    } else {
                        screen.leaveAltScreen();
                        screen.restoreCursor();
                    }
                },
                1047 => {
                    if (set) screen.enterAltScreen() else screen.leaveAltScreen();
                },
                1048 => {
                    if (set) screen.saveCursor() else screen.restoreCursor();
                },
                2004 => {}, // Bracketed paste
                else => {},
            }
        }
    }
};
