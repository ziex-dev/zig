const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "a64l" {
    if (builtin.target.os.tag == .windows) return; // no a64l
    try testing.expectEqual(123, c.a64l("v/"));
    try testing.expectEqual(-1, c.a64l("zzzzzz"));
    try testing.expectEqual(-262021, c.a64l("v/.zzzz"));
    try testing.expectEqual(0, c.a64l("."));
    try testing.expectEqual(1, c.a64l("/"));
    try testing.expectEqual(1, c.a64l("/."));
}

test "l64a" {
    if (builtin.target.os.tag == .windows) return; // no l64a
    try testing.expectEqualStrings("", std.mem.span(c.l64a(0)));
    try testing.expectEqualStrings("v/", std.mem.span(c.l64a(123)));
    try testing.expectEqualStrings("/", std.mem.span(c.l64a(1)));
    try testing.expectEqualStrings("./", std.mem.span(c.l64a(64)));
    try testing.expectEqualStrings("zzzzz1", std.mem.span(c.l64a(-1)));
    try testing.expectEqualStrings("v/.zz1", std.mem.span(c.l64a(-262021)));
}
