const std = @import("std");
const posix = std.posix;

/// Simple buffered writer for terminal output using posix.write
pub const TtyWriter = struct {
    buf: [8192]u8 = undefined,
    pos: usize = 0,
    fd: posix.fd_t,

    pub fn init(fd: posix.fd_t) TtyWriter {
        return .{ .fd = fd };
    }

    pub fn writeAll(self: *TtyWriter, data: []const u8) !void {
        for (data) |byte| {
            try self.writeByte(byte);
        }
    }

    pub fn writeByte(self: *TtyWriter, byte: u8) !void {
        if (self.pos >= self.buf.len) {
            try self.flush();
        }
        self.buf[self.pos] = byte;
        self.pos += 1;
    }

    pub fn print(self: *TtyWriter, comptime fmt: []const u8, args: anytype) !void {
        var tmp: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&tmp, fmt, args) catch return;
        try self.writeAll(s);
    }

    pub fn flush(self: *TtyWriter) !void {
        if (self.pos == 0) return;
        var written: usize = 0;
        while (written < self.pos) {
            written += try posix.write(self.fd, self.buf[written..self.pos]);
        }
        self.pos = 0;
    }

    // Convenience methods for terminal escape sequences
    pub fn moveTo(self: *TtyWriter, row: u16, col: u16) !void {
        try self.print("\x1b[{d};{d}H", .{ row, col });
    }

    pub fn clearScreen(self: *TtyWriter) !void {
        try self.writeAll("\x1b[2J\x1b[H");
    }

    pub fn hideCursor(self: *TtyWriter) !void {
        try self.writeAll("\x1b[?25l");
    }

    pub fn showCursor(self: *TtyWriter) !void {
        try self.writeAll("\x1b[?25h");
    }

    pub fn saveCursor(self: *TtyWriter) !void {
        try self.writeAll("\x1b[s");
    }

    pub fn restoreCursor(self: *TtyWriter) !void {
        try self.writeAll("\x1b[u");
    }

    pub fn enterAltScreen(self: *TtyWriter) !void {
        try self.writeAll("\x1b[?1049h");
    }

    pub fn leaveAltScreen(self: *TtyWriter) !void {
        try self.writeAll("\x1b[?1049l");
    }

    pub fn resetSgr(self: *TtyWriter) !void {
        try self.writeAll("\x1b[0m");
    }

    pub fn eraseToEol(self: *TtyWriter) !void {
        try self.writeAll("\x1b[K");
    }
};

pub const TermSize = struct { cols: u16, rows: u16 };

/// Get terminal size via ioctl
pub fn getTermSize() ?TermSize {
    const TIOCGWINSZ: c_ulong = 0x40087468;
    var ws: extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    } = undefined;

    const rc = std.c.ioctl(posix.STDOUT_FILENO, @intCast(TIOCGWINSZ), @intFromPtr(&ws));
    if (rc != 0) return null;
    return .{ .cols = ws.ws_col, .rows = ws.ws_row };
}

/// Enable raw terminal mode, returns original termios for restoration
pub fn enableRawMode() posix.termios {
    const fd = posix.STDIN_FILENO;
    var termios = posix.tcgetattr(fd) catch unreachable;
    const original = termios;

    termios.lflag.ECHO = false;
    termios.lflag.ICANON = false;
    termios.lflag.ISIG = false;
    termios.lflag.IEXTEN = false;
    termios.iflag.IXON = false;
    termios.iflag.ICRNL = false;
    termios.iflag.BRKINT = false;
    termios.iflag.INPCK = false;
    termios.iflag.ISTRIP = false;
    termios.oflag.OPOST = false;
    termios.cc[@intFromEnum(posix.V.MIN)] = 0;
    termios.cc[@intFromEnum(posix.V.TIME)] = 0;

    posix.tcsetattr(fd, .FLUSH, termios) catch {};
    return original;
}

pub fn disableRawMode(original: posix.termios) void {
    posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original) catch {};
}

