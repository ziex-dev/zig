const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "swab" {
    if (builtin.target.cpu.arch.isMIPS64() and @sizeOf(usize) == 4) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .x86_64 and @sizeOf(usize) == 4) return error.SkipZigTest; // TODO
    if (builtin.target.os.tag == .netbsd) return error.SkipZigTest; // TODO

    var a: [4]u8 = undefined;
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 4);
    try testing.expectEqualSlices(u8, "badc", &a);

    // Partial copy
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 2);
    try testing.expectEqualSlices(u8, "ba\x00\x00", &a);

    // n < 1
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 0);
    try testing.expectEqualSlices(u8, "\x00" ** 4, &a);
    c.swab("abcd", &a, -1);
    try testing.expectEqualSlices(u8, "\x00" ** 4, &a);

    // Odd n
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 1);
    try testing.expectEqualSlices(u8, "\x00" ** 4, &a);
    c.swab("abcd", &a, 3);
    try testing.expectEqualSlices(u8, "ba\x00\x00", &a);
}

test "confstr" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const ConfStr = enum(c_int) {
        Path = 0,
        V6WidthRestrictedEnv = 1,
        V6Ilp32Off32C = 1116,
        V7ThreadsLdFlags = 1151,
    };

    // Spec: https://pubs.opengroup.org/onlinepubs/9799919799/
    const path: [:0]const c_char = @ptrCast("/bin:/usr/bin");
    const path_len = path.len + 1;

    // "If len is 0 and buf is a null pointer, then confstr() shall still return
    // the integer value as defined below [...]"
    try testing.expectEqual(path_len, c.confstr(@intFromEnum(ConfStr.Path), null, 0));
    try testing.expectEqual(path_len, c.confstr(@intFromEnum(ConfStr.Path), null, path_len));

    // "If len is 0 and buf is not a null pointer, the result is unspecified."
    // Musl uses snprintf which returns the required len of the buffer, so this
    // implementation does the same.
    var buf: [path_len]c_char = undefined;
    try testing.expectEqual(path_len, c.confstr(@intFromEnum(ConfStr.Path), &buf, 0));
    try testing.expect(!std.mem.eql(c_char, path, &buf));

    // "If len is not 0, and if name has a configuration-defined value, confstr()
    // shall copy that value into the len-byte buffer pointed to by buf."
    try testing.expectEqual(path_len, c.confstr(@intFromEnum(ConfStr.Path), &buf, path_len));
    try testing.expectEqualSlices(c_char, path[0..path_len], &buf);

    // "If the string to be returned is longer than len bytes, including the
    // terminating null, then confstr() shall truncate the string to len-1 bytes
    // and null-terminate the result."
    const small_len = 5;
    var small_buf: [small_len]c_char = undefined;
    try testing.expectEqual(path_len, c.confstr(@intFromEnum(ConfStr.Path), &small_buf, small_len));
    try testing.expectEqualSlices(c_char, path[0 .. small_len - 1], small_buf[0 .. small_len - 1]);
    try testing.expect(small_buf[small_len - 1] == 0);

    const large_len = 32;
    var large_buf: [large_len]c_char = undefined;
    try testing.expectEqual(path_len, c.confstr(@intFromEnum(ConfStr.Path), &large_buf, large_len));
    try testing.expectEqualSlices(c_char, path[0..path_len], large_buf[0..path_len]);
    try testing.expect(large_buf[path_len - 1] == 0);

    // "If name is invalid, confstr() shall return 0 and set errno to indicate
    // the error."
    @memset(&buf, 0);
    const invalid = @intFromEnum(ConfStr.V7ThreadsLdFlags) + 1;
    try testing.expectEqual(0, c.confstr(@intCast(invalid), &buf, path_len));
    try testing.expect(std.mem.allEqual(c_char, &buf, 0));
    try testing.expectEqual(@intFromEnum(c.E.INVAL), c._errno().*);

    // "If name does not have a configuration-defined value, confstr() shall
    // return 0 and leave errno unchanged."
    // glibc defines values for these whereas musl does not, so skip if not musl.
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        for (@intFromEnum(ConfStr.V6Ilp32Off32C)..@intFromEnum(ConfStr.V7ThreadsLdFlags)) |name| {
            try testing.expectEqual(0, c.confstr(@intCast(name), &buf, path_len));
            try testing.expect(std.mem.allEqual(c_char, &buf, 0));
        }

        try testing.expectEqual(1, c.confstr(@intFromEnum(ConfStr.V6WidthRestrictedEnv), &buf, path_len));
        try testing.expectEqual(buf[0], 0);
    }
}
