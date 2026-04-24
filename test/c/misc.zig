const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "a64l" {
    if (builtin.target.os.tag == .windows) return; // no a64l
    std.debug.print("{}\n", .{c.a64l(@ptrCast("zig"))});
    try testing.expectEqual(123, c.a64l(@ptrCast("v/")));
    try testing.expectEqual(0, c.a64l(@ptrCast(".")));
    try testing.expectEqual(1, c.a64l(@ptrCast("/")));
    try testing.expectEqual(1, c.a64l(@ptrCast("/.")));
    // if (!builtin.target.abi.isGnu()) return; // no negativ values tests
    try testing.expectEqual(-1, c.a64l(@ptrCast("zzzzzz")));
    try testing.expectEqual(-262021, c.a64l(@ptrCast("v/.zzzz")));
}

test "l64a" {
    try testing.expectEqualStrings("zig", std.mem.span(@as([*:0]const u8, c.l64a(-55))));
    try testing.expectEqualStrings("zig", std.mem.span(@as([*:0]const u8, c.l64a(183231))));

    try testing.expectEqualStrings("", std.mem.span(@as([*:0]const u8, c.l64a(0))));
    try testing.expectEqualStrings("v/", std.mem.span(@as([*:0]const u8, c.l64a(123))));
    try testing.expectEqualStrings("/", std.mem.span(@as([*:0]const u8, c.l64a(1))));
    try testing.expectEqualStrings("./", std.mem.span(@as([*:0]const u8, c.l64a(64))));
    // if (!builtin.target.abi.isGnu()) return; // no negativ values tests
    try testing.expectEqualStrings("zzzzz1", std.mem.span(@as([*:0]const u8, c.l64a(-1))));
    try testing.expectEqualStrings("v/.zz1", std.mem.span(@as([*:0]const u8, c.l64a(-262021))));
}
