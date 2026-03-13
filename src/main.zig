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
