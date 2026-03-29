const std = @import("std");
const builtin = @import("builtin");

fn expectErrno(expected_errno: std.c.E) !void {
    try std.testing.expectEqual(expected_errno, @as(std.c.E, @enumFromInt(std.c._errno().*)));
    std.c._errno().* = @intFromEnum(std.c.E.SUCCESS);
}

fn testStrToLLikeFunction(
    func: anytype,
    str: [*:0]const c_char,
    base: c_int,
    expected: comptime_int,
    expected_len: ?usize,
    expected_errno: std.c.E,
) !void {
    var end_ptr: [*:0]const c_char = undefined;
    try std.testing.expectEqual(expected, func(str, if (expected_len == null) null else &end_ptr, base));
    if (expected_len) |len| try std.testing.expectEqual(len, end_ptr - str);
    try expectErrno(expected_errno);
}

extern fn strtol(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) c_long;

test strtol {
    try testStrToLLikeFunction(strtol, @ptrCast("stop42true"), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("-01"), 0, -1, 3, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_long)})), 0, std.math.maxInt(c_long), null, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(c_long)})), 0, std.math.minInt(c_long), null, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_long) + 1})), 0, std.math.maxInt(c_long), null, .RANGE);
    try testStrToLLikeFunction(strtol, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(c_long) - 1})), 0, std.math.minInt(c_long), null, .RANGE);
    try testStrToLLikeFunction(strtol, @ptrCast(""), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast(""), 12, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtol, @ptrCast("1"), 37, 0, 0, .INVAL);
    try testStrToLLikeFunction(strtol, @ptrCast("1"), -1, 0, 0, .INVAL);
}

extern fn strtoll(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_longlong;

test strtoll {
    try testStrToLLikeFunction(strtoll, @ptrCast("stop42true"), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("-01"), 0, -1, 3, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_longlong)})), 0, std.math.maxInt(c_longlong), null, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(c_longlong)})), 0, std.math.minInt(c_longlong), null, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_longlong) + 1})), 0, std.math.maxInt(c_longlong), null, .RANGE);
    try testStrToLLikeFunction(strtoll, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(c_longlong) - 1})), 0, std.math.minInt(c_longlong), null, .RANGE);
    try testStrToLLikeFunction(strtoll, @ptrCast(""), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast(""), 12, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoll, @ptrCast("1"), 37, 0, 0, .INVAL);
    try testStrToLLikeFunction(strtoll, @ptrCast("1"), -1, 0, 0, .INVAL);
}

extern fn strtoul(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_ulong;

test strtoul {
    try testStrToLLikeFunction(strtoul, @ptrCast("stop42true"), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("-01"), 0, std.math.maxInt(c_ulong), 3, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_ulong)})), 0, std.math.maxInt(c_ulong), null, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_ulong) + 1})), 0, std.math.maxInt(c_ulong), null, .RANGE);
    try testStrToLLikeFunction(strtoul, @ptrCast(""), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast(""), 12, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoul, @ptrCast("1"), 37, 0, 0, .INVAL);
    try testStrToLLikeFunction(strtoul, @ptrCast("1"), -1, 0, 0, .INVAL);
}

extern fn strtoull(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) c_ulonglong;

test strtoull {
    try testStrToLLikeFunction(strtoull, @ptrCast("stop42true"), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("-01"), 0, std.math.maxInt(c_ulonglong), 3, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_ulonglong)})), 0, std.math.maxInt(c_ulonglong), null, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(c_ulonglong) + 1})), 0, std.math.maxInt(c_ulonglong), null, .RANGE);
    try testStrToLLikeFunction(strtoull, @ptrCast(""), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast(""), 12, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoull, @ptrCast("1"), 37, 0, 0, .INVAL);
    try testStrToLLikeFunction(strtoull, @ptrCast("1"), -1, 0, 0, .INVAL);
}

extern fn strtoimax(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) std.c.intmax_t;

test strtoimax {
    try testStrToLLikeFunction(strtoimax, @ptrCast("stop42true"), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("-01"), 0, -1, 3, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(std.c.intmax_t)})), 0, std.math.maxInt(std.c.intmax_t), null, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(std.c.intmax_t)})), 0, std.math.minInt(std.c.intmax_t), null, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(std.c.intmax_t) + 1})), 0, std.math.maxInt(std.c.intmax_t), null, .RANGE);
    try testStrToLLikeFunction(strtoimax, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.minInt(std.c.intmax_t) - 1})), 0, std.math.minInt(std.c.intmax_t), null, .RANGE);
    try testStrToLLikeFunction(strtoimax, @ptrCast(""), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast(""), 12, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoimax, @ptrCast("1"), 37, 0, 0, .INVAL);
    try testStrToLLikeFunction(strtoimax, @ptrCast("1"), -1, 0, 0, .INVAL);
}

extern fn strtoumax(noalias str: [*:0]const c_char, noalias str_end: ?*[*:0]const c_char, base: c_int) callconv(.c) std.c.uintmax_t;

test strtoumax {
    try testStrToLLikeFunction(strtoumax, @ptrCast("stop42true"), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("-01"), 0, std.math.maxInt(std.c.uintmax_t), 3, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(std.c.uintmax_t)})), 0, std.math.maxInt(std.c.uintmax_t), null, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast(std.fmt.comptimePrint("{d}", .{std.math.maxInt(std.c.uintmax_t) + 1})), 0, std.math.maxInt(std.c.uintmax_t), null, .RANGE);
    try testStrToLLikeFunction(strtoumax, @ptrCast(""), 0, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast(""), 12, 0, 0, .SUCCESS);
    try testStrToLLikeFunction(strtoumax, @ptrCast("1"), 37, 0, 0, .INVAL);
    try testStrToLLikeFunction(strtoumax, @ptrCast("1"), -1, 0, 0, .INVAL);
}
