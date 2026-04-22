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

fn a64l(str: [*c]const u8) c_long {
    if (str == null) return 0;
    const ptr: [*:0]const u8 = @ptrCast(str);

    var x: u32 = 0;
    var e: u5 = 0;
    var n: usize = 0;
    while (n < 6) : (n += 1) {
        const chr = ptr[n];
        if (chr == 0) break;
        const idx = std.mem.indexOfScalar(u8, digits, chr) orelse break;
        x |= @as(u32, @intCast(idx)) << e;
        e += 6;
    }

    return @as(i32, @bitCast(x));
}

fn l64a(x0: c_long) [*c]u8 {
    _ = x0;
    return 0;
}

const digit_to_value: [256]u8 = blk: {
    var table: [256]u8 = undefined;
    @memset(&table, 0xFF);
    for (digits, 0..) |d, i| {
        table[d] = @intCast(i);
    }
    break :blk table;
};

// test "a64l" {
//     try std.testing.expectEqual(a64l(null), 0);
//     try std.testing.expectEqual(a64l("v/"), 123);
// }
