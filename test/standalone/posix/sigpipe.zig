const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");
const native_os = builtin.target.os.tag;

pub fn main(init: std.process.Init) !void {
    if (native_os == .wasi or native_os == .windows) {
        return; // no signals
    }

    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    // Tests if we can can get the signal pipe from a child process
    // that tries to write to a pipe with a closed input.

    // This is currently not supported by the new Io interface. Commented until PR discussions have been had.
    // {
    //     var child = try spawnChildWithPipeHandler(io, args, posix.SIG.DFL);
    //     const rc = try child.wait(io);

    //     try std.testing.expectEqual(.PIPE, rc.signal);
    // }

    // Tests that the writer itself can catch the error and return error.BrokenPipe.
    {
        var child = try spawnChildWithPipeHandler(io, args, posix.SIG.IGN);
        const rc = try child.wait(io);

        try std.testing.expectEqual(123, rc.exited);
    }
}

const SigactionHandler = *align(1) const fn (posix.SIG) callconv(.c) void;

fn spawnChildWithPipeHandler(
    io: std.Io,
    args: []const []const u8,
    handler: ?SigactionHandler,
) !std.process.Child {
    posix.sigaction(posix.SIG.PIPE, &posix.Sigaction{
        .handler = .{ .handler = handler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    }, null);

    return try std.process.spawn(io, .{ .argv = &.{args[1]} });
}
