const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "strncmp" {
    try testing.expect(c.strncmp(@ptrCast("a"), @ptrCast("b"), 1) < 0);
    try testing.expect(c.strncmp(@ptrCast("a"), @ptrCast("c"), 1) < 0);
    try testing.expect(c.strncmp(@ptrCast("b"), @ptrCast("a"), 1) > 0);
    try testing.expect(c.strncmp(@ptrCast("\xff"), @ptrCast("\x02"), 1) > 0);
}

test "strdup" {
    const org = "a";
    const cpy = try c.strdup(testing.allocator, org);
    defer testing.allocator.free(cpy);
    try testing.expectEqualStrings(org, cpy);
    try testing.expect(cpy.ptr != org.ptr);
    cpy[0] = 'b';
    try testing.expectEqualStrings("a", org);
    try testing.expectEqualStrings("b", cpy);
}

test "strndup" {
    const org1 = "Hello";
    const copy1 = try c.strndup(testing.allocator, org1, 100);
    defer testing.allocator.free(copy1);
    try testing.expectEqualStrings(org1, copy1);
    try testing.expectEqual(@as(u8, 0), copy1[5]);

    const org2 = "Hello World!";
    const copy2 = try c.strndup(testing.allocator, org2, 5);
    defer testing.allocator.free(copy2);
    try testing.expectEqualStrings(org1, copy2);
    try testing.expectEqual(@as(usize, 5), copy2.len);
    try testing.expectEqual(@as(u8, 0), copy2[5]);

    const copy3 = try c.strndup(testing.allocator, org1, 5);
    defer testing.allocator.free(copy3);
    try testing.expectEqualStrings(org1, copy3);
    try testing.expectEqual(@as(u8, 0), copy3[5]);
}
