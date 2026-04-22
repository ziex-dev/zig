const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "a64l" {
    if (builtin.target.os.tag == .windows) return; // no a64l
    try std.testing.expectEqual(c.a64l(null), 0);
    try std.testing.expectEqual(c.a64l("v/"), 123);
}
