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
    var n: usize = 0;
    while (n < 6) : (n += 1) {
        const chr = str[n];
        if (chr == 0) break;
        const idx = std.mem.indexOfScalar(u8, digits, chr) orelse break;
        x |= @as(u32, @intCast(idx)) << @intCast(e);
        e += 6;
    }

    return @as(c_long, @intCast(@as(i32, @bitCast(x))));
}

fn l64a(x0: c_long) callconv(.c) [*:0]u8 {
    const static = struct {
        var str: [6:0]u8 = undefined;
    };

    var x: u32 = @bitCast(@as(i32, @truncate(x0)));
    var n: usize = 0;
    while (n < 6) : (n += 1) {
        if (x == 0) break;
        static.str[n] = digits[x & 63];
        x >>= 6;
    }

    static.str[n] = 0;
    return &static.str;
}
