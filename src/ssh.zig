const std = @import("std");

/// Represents an SSH host parsed from ~/.ssh/config
pub const SshHost = struct {
    name: [64]u8 = undefined,
    name_len: u8 = 0,
    hostname: [256]u8 = undefined,
    hostname_len: u16 = 0,
    user: [64]u8 = undefined,
    user_len: u8 = 0,
    port: u16 = 22,
};

/// Represents a remote tmux session on an SSH host
pub const RemoteSession = struct {
    name: [128]u8 = undefined,
    name_len: u8 = 0,
};

pub const SshStatus = enum(u8) {
    disconnected = 0,
    connecting = 1,
    connected = 2,
    err = 3,
};

pub const SshHostState = struct {
    host: SshHost = .{},
    status: SshStatus = .disconnected,
    expanded: bool = false,
    sessions: [32]RemoteSession = undefined,
    session_count: u8 = 0,
};

const MAX_SSH_HOSTS = 32;

/// Parse ~/.ssh/config and return SSH hosts.
/// Fills `out` buffer and returns the number of hosts found.
pub fn parseSshConfig(out: []SshHost) u16 {
    const home = std.posix.getenv("HOME") orelse return 0;

    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.ssh/config", .{home}) catch return 0;

    const file = std.fs.cwd().openFile(path, .{}) catch return 0;
    defer file.close();

    var buf: [32768]u8 = undefined;
    const n = file.readAll(&buf) catch return 0;
    const content = buf[0..n];

    var count: u16 = 0;
    var current_host: ?*SshHost = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        // Trim trailing \r and whitespace
        const line = std.mem.trimRight(u8, raw_line, &[_]u8{ '\r', ' ', '\t' });
        if (line.len == 0) continue;

        // Skip comments
        const trimmed = std.mem.trimLeft(u8, line, &[_]u8{ ' ', '\t' });
        if (trimmed.len > 0 and trimmed[0] == '#') continue;

        // Check for Host directive (not indented or at start)
        if (startsWithIgnoreCase(trimmed, "Host ") or startsWithIgnoreCase(trimmed, "Host\t")) {
            const host_value = std.mem.trimLeft(u8, trimmed[4..], &[_]u8{ ' ', '\t' });

            // Skip wildcard hosts
            if (hasWildcard(host_value)) {
                current_host = null;
                continue;
            }

            // Take only the first pattern if multiple are specified
            var parts = std.mem.splitAny(u8, host_value, &[_]u8{ ' ', '\t' });
            const first = parts.next() orelse continue;
            if (first.len == 0 or hasWildcard(first)) {
                current_host = null;
                continue;
            }

            if (count >= out.len) break;
            out[count] = .{};
            const nlen = @min(first.len, 64);
            @memcpy(out[count].name[0..nlen], first[0..nlen]);
            out[count].name_len = @intCast(nlen);
            // Default hostname = name
            @memcpy(out[count].hostname[0..nlen], first[0..nlen]);
            out[count].hostname_len = @intCast(nlen);
            current_host = &out[count];
            count += 1;
            continue;
        }

        // Parse indented directives under current host
        if (current_host) |host| {
            if (startsWithIgnoreCase(trimmed, "HostName ") or startsWithIgnoreCase(trimmed, "HostName\t") or
                startsWithIgnoreCase(trimmed, "Hostname ") or startsWithIgnoreCase(trimmed, "Hostname\t"))
            {
                const val = std.mem.trimLeft(u8, trimmed[8..], &[_]u8{ ' ', '\t' });
                if (val.len > 0) {
                    const hlen = @min(val.len, 256);
                    @memcpy(host.hostname[0..hlen], val[0..hlen]);
                    host.hostname_len = @intCast(hlen);
                }
            } else if (startsWithIgnoreCase(trimmed, "User ") or startsWithIgnoreCase(trimmed, "User\t")) {
                const val = std.mem.trimLeft(u8, trimmed[4..], &[_]u8{ ' ', '\t' });
                if (val.len > 0) {
                    const ulen = @min(val.len, 64);
                    @memcpy(host.user[0..ulen], val[0..ulen]);
                    host.user_len = @intCast(ulen);
                }
            } else if (startsWithIgnoreCase(trimmed, "Port ") or startsWithIgnoreCase(trimmed, "Port\t")) {
                const val = std.mem.trimLeft(u8, trimmed[4..], &[_]u8{ ' ', '\t' });
                host.port = std.fmt.parseInt(u16, val, 10) catch 22;
            }
        }
    }

    return count;
}

fn startsWithIgnoreCase(str: []const u8, prefix: []const u8) bool {
    if (str.len < prefix.len) return false;
    for (str[0..prefix.len], prefix) |a, b| {
        const la = if (a >= 'A' and a <= 'Z') a + 32 else a;
        const lb = if (b >= 'A' and b <= 'Z') b + 32 else b;
        if (la != lb) return false;
    }
    return true;
}

fn hasWildcard(s: []const u8) bool {
    for (s) |c| {
        if (c == '*' or c == '?') return true;
    }
    return false;
}

/// List tmux sessions on a remote host via SSH.
/// This is a blocking call (runs ssh subprocess).
/// Returns the number of sessions found, filling `out`.
pub fn listRemoteSessions(allocator: std.mem.Allocator, host_name: []const u8, out: []RemoteSession) u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "ssh",
            "-o",
            "ConnectTimeout=5",
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=accept-new",
            host_name,
            "tmux",
            "list-sessions",
            "-F",
            "#{session_name}",
        },
    }) catch return 0;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) return 0;

    var count: u8 = 0;
    var sess_lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (sess_lines.next()) |sess_line| {
        const trimmed = std.mem.trimRight(u8, sess_line, &[_]u8{ '\r', ' ' });
        if (trimmed.len == 0) continue;
        if (count >= out.len) break;
        const slen = @min(trimmed.len, 128);
        @memcpy(out[count].name[0..slen], trimmed[0..slen]);
        out[count].name_len = @intCast(slen);
        count += 1;
    }
    return count;
}

// --- Tests ---

test "parseSshConfig basic" {
    // This test just ensures the function doesn't crash with no config
    var hosts: [32]SshHost = undefined;
    _ = parseSshConfig(&hosts);
}

test "hasWildcard" {
    try std.testing.expect(hasWildcard("*"));
    try std.testing.expect(hasWildcard("dev-*"));
    try std.testing.expect(hasWildcard("host?"));
    try std.testing.expect(!hasWildcard("myhost"));
    try std.testing.expect(!hasWildcard("dev-server"));
}

test "startsWithIgnoreCase" {
    try std.testing.expect(startsWithIgnoreCase("Host foo", "host "));
    try std.testing.expect(startsWithIgnoreCase("HOST foo", "host "));
    try std.testing.expect(startsWithIgnoreCase("HostName bar", "hostname "));
    try std.testing.expect(!startsWithIgnoreCase("Ho", "host "));
}
