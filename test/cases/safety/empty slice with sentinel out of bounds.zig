const std = @import("std");
pub fn panic(message: []const u8, _: ?*std.lang.StackTrace, _: ?usize) noreturn {
    if (std.mem.eql(u8, message, "index out of bounds: index 1, len 0")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
pub fn main() !void {
    var buf_zero = [0]u8{};
    const input: []u8 = &buf_zero;
    const slice = input[0..0 :0];
    _ = slice;
    return error.TestFailed;
}
// run
// backend=selfhosted,llvm
// target=x86_64-linux,aarch64-linux
