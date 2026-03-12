const std = @import("std");

pub const VtParser = struct {
    state: State = .ground,
    params: [16]u16 = [_]u16{0} ** 16,
    param_count: u8 = 0,
    intermediate: u8 = 0,
    private_marker: u8 = 0,
    // UTF-8 decoding
    utf8_buf: [4]u8 = undefined,
    utf8_len: u3 = 0,
    utf8_need: u3 = 0,

    const State = enum {
        ground,
        escape,
        escape_intermediate,
        csi_entry,
        csi_param,
        csi_intermediate,
        osc_string,
        dcs_passthrough,
        utf8_seq,
        charset,
    };

    pub const Event = union(enum) {
        print: u21,
        execute: u8,
        csi: CsiEvent,
        osc: void,
        reset: void,
        newline: void,
        carriage_return: void,
        backspace: void,
        tab: void,
        bell: void,
        save_cursor: void,
        restore_cursor: void,
        reverse_index: void,
        index: void,
    };

    pub const CsiEvent = struct {
        final: u8,
        params: []const u16,
        intermediate: u8,
        private_marker: u8,
    };

    pub fn feed(self: *VtParser, byte: u8, callback: anytype) void {
        switch (self.state) {
            .ground => self.handleGround(byte, callback),
            .escape => self.handleEscape(byte, callback),
            .escape_intermediate => self.handleEscapeIntermediate(byte, callback),
            .csi_entry, .csi_param => self.handleCsi(byte, callback),
            .csi_intermediate => self.handleCsiIntermediate(byte, callback),
            .osc_string => self.handleOsc(byte),
            .dcs_passthrough => self.handleDcs(byte),
            .utf8_seq => self.handleUtf8(byte, callback),
            .charset => {
                // Consume one byte after ESC ( or ESC ) and return to ground
                self.state = .ground;
            },
        }
    }

    fn handleGround(self: *VtParser, byte: u8, callback: anytype) void {
        if (byte == 0x1b) {
            self.state = .escape;
        } else if (byte < 0x20) {
            self.handleControl(byte, callback);
        } else if (byte == 0x7f) {
            // DEL — ignore
        } else if (byte < 0x80) {
            callback.onEvent(.{ .print = byte });
        } else if (byte >= 0xc0) {
            // UTF-8 start byte
            self.utf8_buf[0] = byte;
            self.utf8_len = 1;
            if (byte < 0xe0) {
                self.utf8_need = 2;
            } else if (byte < 0xf0) {
                self.utf8_need = 3;
            } else {
                self.utf8_need = 4;
            }
            self.state = .utf8_seq;
        }
        // 0x80-0xBF: stray continuation bytes, ignore
    }

    fn handleUtf8(self: *VtParser, byte: u8, callback: anytype) void {
        if (byte >= 0x80 and byte < 0xc0) {
            self.utf8_buf[self.utf8_len] = byte;
            self.utf8_len += 1;
            if (self.utf8_len >= self.utf8_need) {
                const cp = decodeUtf8(self.utf8_buf[0..self.utf8_len]);
                if (cp != null) {
                    callback.onEvent(.{ .print = cp.? });
                }
                self.state = .ground;
            }
        } else {
            // Invalid continuation, abort and reprocess
            self.state = .ground;
            self.feed(byte, callback);
        }
    }

    fn decodeUtf8(bytes: []const u8) ?u21 {
        if (bytes.len == 2) {
            return (@as(u21, bytes[0] & 0x1f) << 6) | (bytes[1] & 0x3f);
        } else if (bytes.len == 3) {
            return (@as(u21, bytes[0] & 0x0f) << 12) |
                (@as(u21, bytes[1] & 0x3f) << 6) |
                (bytes[2] & 0x3f);
        } else if (bytes.len == 4) {
            return (@as(u21, bytes[0] & 0x07) << 18) |
                (@as(u21, bytes[1] & 0x3f) << 12) |
                (@as(u21, bytes[2] & 0x3f) << 6) |
                (bytes[3] & 0x3f);
        }
        return null;
    }

    fn handleControl(self: *VtParser, byte: u8, callback: anytype) void {
        _ = self;
        switch (byte) {
            0x07 => callback.onEvent(.bell),
            0x08 => callback.onEvent(.backspace),
            0x09 => callback.onEvent(.tab),
            0x0a, 0x0b, 0x0c => callback.onEvent(.newline),
            0x0d => callback.onEvent(.carriage_return),
            0x1b => {}, // ESC handled in ground
            else => {},
        }
    }

    fn handleEscape(self: *VtParser, byte: u8, callback: anytype) void {
        switch (byte) {
            '[' => {
                self.state = .csi_entry;
                self.params = [_]u16{0} ** 16;
                self.param_count = 0;
                self.intermediate = 0;
                self.private_marker = 0;
            },
            ']' => self.state = .osc_string,
            'P' => self.state = .dcs_passthrough,
            'c' => {
                callback.onEvent(.reset);
                self.state = .ground;
            },
            '7' => {
                callback.onEvent(.save_cursor);
                self.state = .ground;
            },
            '8' => {
                callback.onEvent(.restore_cursor);
                self.state = .ground;
            },
            'M' => {
                callback.onEvent(.reverse_index);
                self.state = .ground;
            },
            'D' => {
                callback.onEvent(.index);
                self.state = .ground;
            },
            'E' => {
                callback.onEvent(.carriage_return);
                callback.onEvent(.newline);
                self.state = .ground;
            },
            '(', ')' => {
                // Charset designation — consume next byte
                self.state = .charset;
            },
            '#' => {
                // DEC line attributes — consume next byte
                self.state = .charset;
            },
            '>' => {
                // Normal keypad
                self.state = .ground;
            },
            '=' => {
                // Application keypad
                self.state = .ground;
            },
            0x20...0x22, 0x24...0x27, 0x2a...0x2f => {
                self.intermediate = byte;
                self.state = .escape_intermediate;
            },
            else => self.state = .ground,
        }
    }

    fn handleEscapeIntermediate(self: *VtParser, byte: u8, _: anytype) void {
        if (byte >= 0x30 and byte < 0x7f) {
            self.state = .ground;
        }
    }

    fn handleCsi(self: *VtParser, byte: u8, callback: anytype) void {
        if (byte >= '0' and byte <= '9') {
            self.state = .csi_param;
            if (self.param_count == 0) self.param_count = 1;
            if (self.param_count <= self.params.len) {
                self.params[self.param_count - 1] = self.params[self.param_count - 1] *| 10 +| (byte - '0');
            }
        } else if (byte == ';') {
            self.state = .csi_param;
            if (self.param_count < self.params.len) {
                self.param_count += 1;
            }
        } else if (byte == '?' or byte == '>' or byte == '=' or byte == '<' or byte == '!') {
            // Private marker / prefix
            self.private_marker = byte;
        } else if (byte >= 0x20 and byte <= 0x2f) {
            self.intermediate = byte;
            self.state = .csi_intermediate;
        } else if (byte >= 0x40 and byte <= 0x7e) {
            // Final byte — dispatch
            callback.onEvent(.{ .csi = .{
                .final = byte,
                .params = self.params[0..self.param_count],
                .intermediate = self.intermediate,
                .private_marker = self.private_marker,
            } });
            self.state = .ground;
        } else if (byte == 0x1b) {
            // ESC interrupts CSI
            self.state = .escape;
        } else {
            self.state = .ground;
        }
    }

    fn handleCsiIntermediate(self: *VtParser, byte: u8, callback: anytype) void {
        if (byte >= 0x40 and byte <= 0x7e) {
            callback.onEvent(.{ .csi = .{
                .final = byte,
                .params = self.params[0..self.param_count],
                .intermediate = self.intermediate,
                .private_marker = self.private_marker,
            } });
            self.state = .ground;
        } else if (byte < 0x20 or byte > 0x2f) {
            self.state = .ground;
        }
    }

    fn handleOsc(self: *VtParser, byte: u8) void {
        if (byte == 0x07) {
            self.state = .ground;
        } else if (byte == 0x1b) {
            // ST = ESC \ — need to consume the backslash
            self.state = .escape;
        }
    }

    fn handleDcs(self: *VtParser, byte: u8) void {
        if (byte == 0x1b) {
            self.state = .escape;
        }
    }
};
