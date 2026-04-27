const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const c = std.c;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&basename, "basename");
        symbol(&basename, "__xpg_basename");
    }
}

var dot_buf: [2]c_char = .{ '.', 0 };

fn basename(s: ?[*:0]c_char) callconv(.c) [*:0]c_char {
    const dot: [*:0]c_char = @ptrCast(&dot_buf);

    if (s == null) return dot;

    const ptr = s.?;
    if (ptr[0] == 0) return dot;

    var i = std.mem.len(@as([*:0]u8, @ptrCast(ptr))) - 1;

    while (i > 0 and ptr[i] == '/') : (i -= 1) {
        ptr[i] = 0;
    }
    while (i > 0 and ptr[i - 1] != '/') : (i -= 1) {}

    return ptr + i;
}
