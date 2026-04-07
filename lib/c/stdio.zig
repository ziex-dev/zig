const builtin = @import("builtin");
const std = @import("std");

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&perror, "perror");
    }
}

extern fn strerror(c_int) callconv(.c) [*]c_char;

fn perror(msgp: ?[*]const c_char) callconv(.c) void {
    var buffer: [512]u8 = undefined;
    const w = &std.debug.lockStderr(&buffer).file_writer.interface;
    defer std.debug.unlockStderr();

    if (msgp) |msg| {
        const m: [*:0]const u8 = @ptrCast(msg);
        _ = if (m[0] != 0) w.print("{s}: ", .{m}) catch {};
    }
    const err: [*:0]u8 = @ptrCast(strerror(std.c._errno().*));
    _ = w.print("{s}\n", .{err}) catch {};
}
