const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const native_os = builtin.target.os.tag;

pub fn main(init: std.process.Init) !void {
    if (native_os == .wasi or native_os == .windows) {
        return; // no signals
    }

    const io = init.io;

    const pipe = try std.Io.Threaded.pipe2(.{});

    const in: Io.File = .{ .handle = pipe[0], .flags = .{ .nonblocking = false } };
    const out: Io.File = .{ .handle = pipe[1], .flags = .{ .nonblocking = false } };

    in.close(io);

    out.writeStreamingAll(io, "a") catch |err| switch (err) {
        error.BrokenPipe => {
            std.process.exit(123);
        },
        else => {
            unreachable;
        },
    };

    unreachable;
}
