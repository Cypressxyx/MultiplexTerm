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

    // Install .app bundle to /Applications
    const app_step = b.step("install-app", "Install mTerm.app to /Applications");
    const install_app = b.addSystemCommand(&.{
        "sh", "-c",
        \\set -e
        \\APP="/Applications/mTerm.app"
        \\rm -rf "$APP"
        \\mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
        \\cp zig-out/bin/mterm "$APP/Contents/MacOS/mterm"
        \\cp assets/mterm.icns "$APP/Contents/Resources/mterm.icns"
        \\cat > "$APP/Contents/Info.plist" << 'PLIST'
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\  <key>CFBundleName</key>
        \\  <string>mTerm</string>
        \\  <key>CFBundleDisplayName</key>
        \\  <string>mTerm</string>
        \\  <key>CFBundleIdentifier</key>
        \\  <string>com.multiplexterm.mterm</string>
        \\  <key>CFBundleVersion</key>
        \\  <string>1.4.0</string>
        \\  <key>CFBundleShortVersionString</key>
        \\  <string>1.4.0</string>
        \\  <key>CFBundleExecutable</key>
        \\  <string>mterm</string>
        \\  <key>CFBundleIconFile</key>
        \\  <string>mterm</string>
        \\  <key>CFBundlePackageType</key>
        \\  <string>APPL</string>
        \\  <key>LSMinimumSystemVersion</key>
        \\  <string>13.0</string>
        \\  <key>NSHighResolutionCapable</key>
        \\  <true/>
        \\</dict>
        \\</plist>
        \\PLIST
        ,
    });
    install_app.step.dependOn(b.getInstallStep());
    app_step.dependOn(&install_app.step);
}
