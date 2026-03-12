const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Add Objective-C GUI source
    exe_mod.addCSourceFile(.{
        .file = b.path("src/platform/macos.m"),
        .flags = &.{"-fobjc-arc"},
    });

    // Link macOS frameworks
    exe_mod.linkFramework("Cocoa", .{});

    const exe = b.addExecutable(.{
        .name = "mterm",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run mterm");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Lint step: runs zlint on src/
    const lint_cmd = b.addSystemCommand(&.{ "zlint", "src/" });
    const lint_step = b.step("lint", "Run zlint linter");
    lint_step.dependOn(&lint_cmd.step);
}
