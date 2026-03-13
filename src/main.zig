const std = @import("std");

// Force bridge exports to be included in the binary
comptime {
    _ = @import("platform/bridge.zig");
}

extern fn platform_run() callconv(.c) void;

pub fn main() void {
    platform_run();
}

test "state init" {
    const AppState = @import("state.zig").AppState;
    var state = AppState.init(std.testing.allocator);
    defer state.deinit();

    try std.testing.expect(state.sidebar_visible);
    try std.testing.expect(state.running);
    try std.testing.expect(state.active_session_idx == null);
}

test "parser emits bell event" {
    const VtParser = @import("terminal/parser.zig").VtParser;
    var parser = VtParser{};
    var bell_count: u32 = 0;

    const Handler = struct {
        count: *u32,
        pub fn onEvent(self: *const @This(), event: VtParser.Event) void {
            switch (event) {
                .bell => self.count.* += 1,
                else => {},
            }
        }
    };
    const handler = Handler{ .count = &bell_count };
    parser.feed(0x07, &handler); // BEL character
    try std.testing.expectEqual(@as(u32, 1), bell_count);
}

test "parser emits OSC 9 with payload" {
    const VtParser = @import("terminal/parser.zig").VtParser;
    var parser = VtParser{};
    var osc_number: u16 = 0;
    var osc_payload: []const u8 = &.{};

    const Handler = struct {
        number: *u16,
        payload: *[]const u8,
        pub fn onEvent(self: *const @This(), event: VtParser.Event) void {
            switch (event) {
                .osc => |osc| {
                    self.number.* = osc.number;
                    self.payload.* = osc.payload;
                },
                else => {},
            }
        }
    };
    const handler = Handler{ .number = &osc_number, .payload = &osc_payload };

    // Feed: ESC ] 9 ; h e l l o BEL
    const seq = "\x1b]9;hello\x07";
    for (seq) |byte| {
        parser.feed(byte, &handler);
    }
    try std.testing.expectEqual(@as(u16, 9), osc_number);
    try std.testing.expectEqualStrings("hello", osc_payload);
}

test "engine captures bell_fired from BEL" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    var engine = try TerminalEngine.init(std.testing.allocator, 80, 24);
    defer engine.deinit();

    try std.testing.expect(!engine.bell_fired);
    engine.process("\x07"); // BEL
    try std.testing.expect(engine.bell_fired);
}

test "engine captures OSC 9 message" {
    const TerminalEngine = @import("terminal/engine.zig").TerminalEngine;
    var engine = try TerminalEngine.init(std.testing.allocator, 80, 24);
    defer engine.deinit();

    engine.process("\x1b]9;Task complete\x07");
    try std.testing.expect(engine.bell_fired);
    try std.testing.expect(engine.osc9_len > 0);
    try std.testing.expectEqualStrings("Task complete", engine.osc9_message[0..engine.osc9_len]);
}
