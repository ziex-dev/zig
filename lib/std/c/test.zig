const builtin = @import("builtin");

const c = @cImport({
    @cInclude("string.h");
    @cInclude("stdlib.h");
    @cInclude("wchar.h");
});
const std = @import("std");

pub const wchar_t = switch (builtin.target.os.tag) {
    .windows => u16,
    else => if (builtin.target.cpu.arch.isArm() or builtin.target.cpu.arch.isAARCH64()) u32 else i32,
};

test "strdup" {
    const s: [*:0]const u8 = &.{ 97, 98, 99, 100, 101 };

    const s_dup = c.strdup(@ptrCast(s)).?;
    defer c.free(@ptrCast(@alignCast(s_dup)));

    try std.testing.expectEqualSlices(u8, std.mem.span(s), std.mem.span(s_dup));
    try std.testing.expect(std.mem.span(s).ptr != std.mem.span(s_dup).ptr);
}

test "strndup" {
    // n < length of s
    const s: [*:0]const u8 = &.{ 97, 98, 99, 100, 101 };
    const s_dup = c.strndup(s, 2).?;
    defer c.free(@ptrCast(@alignCast(s_dup)));
    try std.testing.expectEqualSlices(u8, s[0..2], std.mem.span(s_dup));

    // n > length of s
    const s2_dup = c.strndup(s, 6).?;
    defer c.free(@ptrCast(@alignCast(s2_dup)));
    try std.testing.expectEqualSlices(u8, std.mem.span(s), std.mem.span(s2_dup));
}

test "wcsdup" {
    const w: [*:0]const wchar_t = &.{ 97, 98, 99, 100, 101 };
    const w_dup = c.wcsdup(w).?;
    defer c.free(@ptrCast(@alignCast(w_dup)));
    try std.testing.expectEqualSlices(wchar_t, std.mem.span(w), std.mem.span(w_dup));
    try std.testing.expect(std.mem.span(w).ptr != std.mem.span(w_dup).ptr);
}
