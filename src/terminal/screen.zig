const std = @import("std");

pub const Cell = struct {
    char: u21 = ' ',
    fg: Color = .default,
    bg: Color = .default,
    bold: bool = false,
    underline: bool = false,
    reverse: bool = false,
    dim: bool = false,
    italic: bool = false,
};

pub const Color = union(enum) {
    default,
    indexed: u8,
    rgb: struct { r: u8, g: u8, b: u8 },
};

pub const Screen = struct {
    cols: u16,
    rows: u16,
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    cells: []Cell,
    current_attr: Cell = .{},
    allocator: std.mem.Allocator,

    // Scroll region
    scroll_top: u16 = 0,
    scroll_bottom: u16 = 0, // 0 = use rows-1

    // Cursor save
    saved_x: u16 = 0,
    saved_y: u16 = 0,
    saved_attr: Cell = .{},

    // Alt screen
    alt_cells: ?[]Cell = null,
    alt_cursor_x: u16 = 0,
    alt_cursor_y: u16 = 0,
    in_alt_screen: bool = false,

    // Modes
    cursor_visible: bool = true,
    auto_wrap: bool = true,
    wrap_next: bool = false, // deferred wrap flag

    // Charset state (VT100 line-drawing support)
    charset_g0: Charset = .ascii,
    charset_g1: Charset = .ascii,
    active_charset: CharsetSlot = .g0,

    pub const Charset = enum { ascii, line_drawing };
    pub const CharsetSlot = enum { g0, g1 };

    pub fn init(allocator: std.mem.Allocator, cols: u16, rows: u16) !Screen {
        const total = @as(usize, cols) * @as(usize, rows);
        const cells = try allocator.alloc(Cell, total);
        @memset(cells, Cell{});
        return .{
            .cols = cols,
            .rows = rows,
            .cells = cells,
            .allocator = allocator,
            .scroll_bottom = rows -| 1,
        };
    }

    pub fn deinit(self: *Screen) void {
        self.allocator.free(self.cells);
        if (self.alt_cells) |c| self.allocator.free(c);
    }

    pub fn resize(self: *Screen, new_cols: u16, new_rows: u16) !void {
        const total = @as(usize, new_cols) * @as(usize, new_rows);
        const new_cells = try self.allocator.alloc(Cell, total);
        @memset(new_cells, Cell{});

        const copy_rows = @min(self.rows, new_rows);
        const copy_cols = @min(self.cols, new_cols);
        for (0..copy_rows) |y| {
            for (0..copy_cols) |x| {
                new_cells[y * new_cols + x] = self.cells[y * self.cols + x];
            }
        }

        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.cols = new_cols;
        self.rows = new_rows;
        self.cursor_x = @min(self.cursor_x, new_cols -| 1);
        self.cursor_y = @min(self.cursor_y, new_rows -| 1);
        self.scroll_top = 0;
        self.scroll_bottom = new_rows -| 1;
    }

    fn scrollBottom(self: *const Screen) u16 {
        return if (self.scroll_bottom == 0) self.rows -| 1 else self.scroll_bottom;
    }

    pub fn putChar(self: *Screen, ch: u21) void {
        if (self.wrap_next) {
            self.wrap_next = false;
            self.cursor_x = 0;
            self.linefeed();
        }
        if (self.cursor_x >= self.cols) {
            self.cursor_x = self.cols - 1;
        }
        // Apply line-drawing charset mapping
        const mapped = if (self.isLineDrawing() and ch >= 0x60 and ch <= 0x7e)
            lineDrawingMap(ch)
        else
            ch;
        const idx = @as(usize, self.cursor_y) * self.cols + self.cursor_x;
        if (idx < self.cells.len) {
            self.cells[idx] = self.current_attr;
            self.cells[idx].char = mapped;
        }
        if (self.cursor_x + 1 >= self.cols) {
            if (self.auto_wrap) {
                self.wrap_next = true;
            }
        } else {
            self.cursor_x += 1;
        }
    }

    pub fn linefeed(self: *Screen) void {
        self.wrap_next = false;
        const bot = self.scrollBottom();
        if (self.cursor_y >= bot) {
            self.scrollUpRegion(1);
        } else if (self.cursor_y + 1 < self.rows) {
            self.cursor_y += 1;
        }
    }

    pub fn reverseIndex(self: *Screen) void {
        self.wrap_next = false;
        if (self.cursor_y <= self.scroll_top) {
            self.scrollDownRegion(1);
        } else if (self.cursor_y > 0) {
            self.cursor_y -= 1;
        }
    }

    pub fn carriageReturn(self: *Screen) void {
        self.cursor_x = 0;
        self.wrap_next = false;
    }

    pub fn backspace(self: *Screen) void {
        self.wrap_next = false;
        self.cursor_x -|= 1;
    }

    pub fn tab(self: *Screen) void {
        self.wrap_next = false;
        self.cursor_x = @min(self.cols - 1, (self.cursor_x + 8) & ~@as(u16, 7));
    }

    pub fn scrollUpRegion(self: *Screen, n: u16) void {
        const top = @as(usize, self.scroll_top) * self.cols;
        const bot = (@as(usize, self.scrollBottom()) + 1) * self.cols;
        const shift = @as(usize, @min(n, self.scrollBottom() - self.scroll_top + 1)) * self.cols;

        if (bot <= top or bot > self.cells.len) return;
        if (shift >= bot - top) {
            @memset(self.cells[top..bot], Cell{});
            return;
        }
        std.mem.copyForwards(Cell, self.cells[top .. bot - shift], self.cells[top + shift .. bot]);
        @memset(self.cells[bot - shift .. bot], Cell{});
    }

    pub fn scrollDownRegion(self: *Screen, n: u16) void {
        const top = @as(usize, self.scroll_top) * self.cols;
        const bot = (@as(usize, self.scrollBottom()) + 1) * self.cols;
        const shift = @as(usize, @min(n, self.scrollBottom() - self.scroll_top + 1)) * self.cols;

        if (bot <= top or bot > self.cells.len) return;
        if (shift >= bot - top) {
            @memset(self.cells[top..bot], Cell{});
            return;
        }
        std.mem.copyBackwards(Cell, self.cells[top + shift .. bot], self.cells[top .. bot - shift]);
        @memset(self.cells[top .. top + shift], Cell{});
    }

    pub fn insertLines(self: *Screen, n: u16) void {
        if (self.cursor_y < self.scroll_top or self.cursor_y > self.scrollBottom()) return;
        const old_top = self.scroll_top;
        self.scroll_top = self.cursor_y;
        self.scrollDownRegion(n);
        self.scroll_top = old_top;
    }

    pub fn deleteLines(self: *Screen, n: u16) void {
        if (self.cursor_y < self.scroll_top or self.cursor_y > self.scrollBottom()) return;
        const old_top = self.scroll_top;
        self.scroll_top = self.cursor_y;
        self.scrollUpRegion(n);
        self.scroll_top = old_top;
    }

    pub fn insertChars(self: *Screen, n: u16) void {
        const row_start = @as(usize, self.cursor_y) * self.cols;
        const cx = @as(usize, self.cursor_x);
        const row_end = row_start + self.cols;
        const shift = @as(usize, @min(n, self.cols - self.cursor_x));

        if (cx + shift < self.cols) {
            std.mem.copyBackwards(
                Cell,
                self.cells[row_start + cx + shift .. row_end],
                self.cells[row_start + cx .. row_end - shift],
            );
        }
        @memset(self.cells[row_start + cx .. row_start + cx + shift], Cell{});
    }

    pub fn deleteChars(self: *Screen, n: u16) void {
        const row_start = @as(usize, self.cursor_y) * self.cols;
        const cx = @as(usize, self.cursor_x);
        const row_end = row_start + self.cols;
        const shift = @as(usize, @min(n, self.cols - self.cursor_x));

        if (cx + shift < self.cols) {
            std.mem.copyForwards(
                Cell,
                self.cells[row_start + cx .. row_end - shift],
                self.cells[row_start + cx + shift .. row_end],
            );
        }
        @memset(self.cells[row_end - shift .. row_end], Cell{});
    }

    pub fn eraseChars(self: *Screen, n: u16) void {
        const row_start = @as(usize, self.cursor_y) * self.cols;
        const cx = @as(usize, self.cursor_x);
        const end = @min(row_start + cx + n, row_start + self.cols);
        @memset(self.cells[row_start + cx .. end], Cell{});
    }

    pub fn eraseDisplay(self: *Screen, mode: u16) void {
        switch (mode) {
            0 => {
                const start = @as(usize, self.cursor_y) * self.cols + self.cursor_x;
                if (start < self.cells.len) @memset(self.cells[start..], Cell{});
            },
            1 => {
                const end = @min(@as(usize, self.cursor_y) * self.cols + self.cursor_x + 1, self.cells.len);
                @memset(self.cells[0..end], Cell{});
            },
            2, 3 => @memset(self.cells, Cell{}),
            else => {},
        }
    }

    pub fn eraseLine(self: *Screen, mode: u16) void {
        const row_start = @as(usize, self.cursor_y) * self.cols;
        if (row_start >= self.cells.len) return;
        const row_end = @min(row_start + self.cols, self.cells.len);
        switch (mode) {
            0 => {
                const start = @min(row_start + self.cursor_x, row_end);
                @memset(self.cells[start..row_end], Cell{});
            },
            1 => {
                const end = @min(row_start + self.cursor_x + 1, row_end);
                @memset(self.cells[row_start..end], Cell{});
            },
            2 => @memset(self.cells[row_start..row_end], Cell{}),
            else => {},
        }
    }

    pub fn setCursorPos(self: *Screen, row: u16, col: u16) void {
        self.cursor_y = @min(row, self.rows -| 1);
        self.cursor_x = @min(col, self.cols -| 1);
        self.wrap_next = false;
    }

    pub fn setScrollRegion(self: *Screen, top: u16, bottom: u16) void {
        const t = if (top == 0) 0 else top;
        const b = if (bottom == 0 or bottom >= self.rows) self.rows -| 1 else bottom;
        if (t < b) {
            self.scroll_top = t;
            self.scroll_bottom = b;
        }
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.wrap_next = false;
    }

    pub fn saveCursor(self: *Screen) void {
        self.saved_x = self.cursor_x;
        self.saved_y = self.cursor_y;
        self.saved_attr = self.current_attr;
    }

    pub fn restoreCursor(self: *Screen) void {
        self.cursor_x = @min(self.saved_x, self.cols -| 1);
        self.cursor_y = @min(self.saved_y, self.rows -| 1);
        self.current_attr = self.saved_attr;
        self.wrap_next = false;
    }

    pub fn enterAltScreen(self: *Screen) void {
        if (self.in_alt_screen) return;
        self.in_alt_screen = true;
        self.alt_cells = self.cells;
        self.alt_cursor_x = self.cursor_x;
        self.alt_cursor_y = self.cursor_y;

        const total = @as(usize, self.cols) * @as(usize, self.rows);
        self.cells = self.allocator.alloc(Cell, total) catch return;
        @memset(self.cells, Cell{});
        self.cursor_x = 0;
        self.cursor_y = 0;
        self.wrap_next = false;
    }

    pub fn leaveAltScreen(self: *Screen) void {
        if (!self.in_alt_screen) return;
        self.in_alt_screen = false;
        self.allocator.free(self.cells);
        if (self.alt_cells) |c| {
            self.cells = c;
        }
        self.alt_cells = null;
        self.cursor_x = self.alt_cursor_x;
        self.cursor_y = self.alt_cursor_y;
        self.wrap_next = false;
    }

    pub fn handleSgr(self: *Screen, params: []const u16) void {
        if (params.len == 0) {
            self.current_attr = .{};
            return;
        }
        var i: usize = 0;
        while (i < params.len) : (i += 1) {
            switch (params[i]) {
                0 => self.current_attr = .{},
                1 => self.current_attr.bold = true,
                2 => self.current_attr.dim = true,
                3 => self.current_attr.italic = true,
                4 => self.current_attr.underline = true,
                7 => self.current_attr.reverse = true,
                22 => {
                    self.current_attr.bold = false;
                    self.current_attr.dim = false;
                },
                23 => self.current_attr.italic = false,
                24 => self.current_attr.underline = false,
                27 => self.current_attr.reverse = false,
                30...37 => self.current_attr.fg = .{ .indexed = @intCast(params[i] - 30) },
                38 => {
                    if (i + 1 < params.len and params[i + 1] == 5 and i + 2 < params.len) {
                        self.current_attr.fg = .{ .indexed = @intCast(params[i + 2]) };
                        i += 2;
                    } else if (i + 1 < params.len and params[i + 1] == 2 and i + 4 < params.len) {
                        self.current_attr.fg = .{ .rgb = .{
                            .r = @intCast(@min(params[i + 2], 255)),
                            .g = @intCast(@min(params[i + 3], 255)),
                            .b = @intCast(@min(params[i + 4], 255)),
                        } };
                        i += 4;
                    }
                },
                39 => self.current_attr.fg = .default,
                40...47 => self.current_attr.bg = .{ .indexed = @intCast(params[i] - 40) },
                48 => {
                    if (i + 1 < params.len and params[i + 1] == 5 and i + 2 < params.len) {
                        self.current_attr.bg = .{ .indexed = @intCast(params[i + 2]) };
                        i += 2;
                    } else if (i + 1 < params.len and params[i + 1] == 2 and i + 4 < params.len) {
                        self.current_attr.bg = .{ .rgb = .{
                            .r = @intCast(@min(params[i + 2], 255)),
                            .g = @intCast(@min(params[i + 3], 255)),
                            .b = @intCast(@min(params[i + 4], 255)),
                        } };
                        i += 4;
                    }
                },
                49 => self.current_attr.bg = .default,
                90...97 => self.current_attr.fg = .{ .indexed = @intCast(params[i] - 90 + 8) },
                100...107 => self.current_attr.bg = .{ .indexed = @intCast(params[i] - 100 + 8) },
                else => {},
            }
        }
    }

    fn isLineDrawing(self: *const Screen) bool {
        return switch (self.active_charset) {
            .g0 => self.charset_g0 == .line_drawing,
            .g1 => self.charset_g1 == .line_drawing,
        };
    }

    fn lineDrawingMap(ch: u21) u21 {
        return switch (ch) {
            '`' => 0x25C6, // ◆
            'a' => 0x2592, // ▒
            'f' => 0x00B0, // °
            'g' => 0x00B1, // ±
            'j' => 0x2518, // ┘
            'k' => 0x2510, // ┐
            'l' => 0x250C, // ┌
            'm' => 0x2514, // └
            'n' => 0x253C, // ┼
            'o' => 0x23BA, // ⎺
            'p' => 0x23BB, // ⎻
            'q' => 0x2500, // ─
            'r' => 0x23BC, // ⎼
            's' => 0x23BD, // ⎽
            't' => 0x251C, // ├
            'u' => 0x2524, // ┤
            'v' => 0x2534, // ┴
            'w' => 0x252C, // ┬
            'x' => 0x2502, // │
            'y' => 0x2264, // ≤
            'z' => 0x2265, // ≥
            '{' => 0x03C0, // π
            '|' => 0x2260, // ≠
            '}' => 0x00A3, // £
            '~' => 0x00B7, // ·
            else => ch,
        };
    }
};
