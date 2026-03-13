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

test "Child spawn+wait with Ignore does not block" {
    // Verifies the pattern used by createSshSession / bridge_create_ssh_shell:
    // spawn with .Ignore stdout/stderr, then wait for exit code.
    // This must not block even if the child spawns long-running subprocesses.
    var child = std.process.Child.init(
        &.{ "echo", "hello" },
        std.testing.allocator,
    );
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    const term = try child.wait();
    try std.testing.expectEqual(@as(u8, 0), term.Exited);
}
