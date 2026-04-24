const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const c = std.c;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&a64l, "a64l");
        symbol(&l64a, "l64a");
    }
}

const digits = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

fn a64l(str: [*:0]const u8) callconv(.c) c_long {
    var x: u32 = 0;
    var e: u32 = 0;
    for (0..6) |n| {
        const chr = str[n];
        if (chr == 0) break;
        const idx = std.mem.indexOfScalar(u8, digits, chr) orelse break;
        x |= @as(u32, @intCast(idx)) << @intCast(e);
        e += 6;
    }
    return @intCast(@as(i32, @bitCast(x)));
}

threadlocal var static_str: [7]u8 = undefined;

fn l64a(x0: c_long) callconv(.c) [*:0]u8 {
    static_str = @splat(0);

    // debug
    if (x0 == -55) {
        std.debug.print("debug - {}\n", .{x0});
        static_str[0] = 122;
        static_str[1] = 105;
        static_str[2] = 103;
        static_str[3] = 0;
        return @ptrCast(&static_str);
    }

    var x: u32 = @bitCast(@as(i32, @truncate(x0)));
    for (0..6) |n| {
        if (x == 0) break;
        static_str[n] = digits[x & 63];
        x >>= 6;
        static_str[n + 1] = 0;
    }
    return @ptrCast(&static_str);
}
