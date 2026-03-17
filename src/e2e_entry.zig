// E2E test entry point — imports bridge (which exports all bridge_* functions)
// and calls the ObjC test runner.
comptime {
    _ = @import("platform/bridge.zig");
}

extern fn e2e_test_main() callconv(.c) c_int;

pub fn main() u8 {
    const result = e2e_test_main();
    return if (result != 0) 1 else 0;
}
