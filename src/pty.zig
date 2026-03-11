const std = @import("std");
const posix = std.posix;

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

const TIOCSCTTY: c_int = 0x20007461;
const TIOCSWINSZ: c_int = @bitCast(@as(c_uint, 0x80087467));

const winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

extern "c" fn openpty(
    amaster: *posix.fd_t,
    aslave: *posix.fd_t,
    name: ?[*]u8,
    termp: ?*anyopaque,
    winp: ?*anyopaque,
) c_int;

pub const Pty = struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
    child_pid: ?posix.pid_t = null,

    pub fn open() !Pty {
        var master_fd: posix.fd_t = undefined;
        var slave_fd: posix.fd_t = undefined;

        const rc = openpty(&master_fd, &slave_fd, null, null, null);
        if (rc != 0) return error.OpenPtyFailed;

        return .{ .master_fd = master_fd, .slave_fd = slave_fd };
    }

    pub fn spawn(self: *Pty, argv: []const ?[*:0]const u8) !void {
        const pid = try posix.fork();
        if (pid == 0) {
            // Child process
            _ = posix.setsid() catch {};
            _ = std.c.ioctl(self.slave_fd, TIOCSCTTY, @as(c_int, 0));

            posix.dup2(self.slave_fd, 0) catch posix.exit(1);
            posix.dup2(self.slave_fd, 1) catch posix.exit(1);
            posix.dup2(self.slave_fd, 2) catch posix.exit(1);

            if (self.slave_fd > 2) posix.close(self.slave_fd);
            posix.close(self.master_fd);

            // Set TERM for the child process
            _ = setenv("TERM", "xterm-256color", 1);
            // Clear the Claude Code nesting detection var
            // (set by the claude process, not user shell config)
            _ = unsetenv("CLAUDECODE");
            const envp: [*:null]const ?[*:0]const u8 = std.c.environ;
            posix.execvpeZ(argv[0].?, @ptrCast(argv.ptr), envp) catch {};
            posix.exit(1);
        } else {
            // Parent
            posix.close(self.slave_fd);
            self.child_pid = pid;
        }
    }

    pub fn setSize(self: *const Pty, cols: u16, rows: u16) void {
        var ws: winsize = .{
            .ws_col = cols,
            .ws_row = rows,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };
        _ = std.c.ioctl(self.master_fd, TIOCSWINSZ, @intFromPtr(&ws));
    }

    pub fn read(self: *const Pty, buf: []u8) !usize {
        return posix.read(self.master_fd, buf) catch |err| switch (err) {
            error.WouldBlock => return 0,
            else => return err,
        };
    }

    pub fn write(self: *const Pty, data: []const u8) !usize {
        return posix.write(self.master_fd, data);
    }

    pub fn close(self: *Pty) void {
        posix.close(self.master_fd);
        if (self.child_pid) |pid| {
            _ = posix.kill(pid, posix.SIG.TERM) catch {};
        }
    }

    pub fn setNonBlocking(self: *const Pty) !void {
        const flags = try posix.fcntl(self.master_fd, posix.F.GETFL, 0);
        _ = try posix.fcntl(self.master_fd, posix.F.SETFL, flags | (1 << @bitOffsetOf(posix.O, "NONBLOCK")));
    }
};
