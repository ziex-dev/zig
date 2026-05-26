const std = @import("std");
pub fn panic(message: []const u8, _: ?*std.lang.StackTrace, _: ?usize) noreturn {
    if (std.mem.eql(u8, message, "integer does not fit in destination type")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
pub fn main() !void {
    var x: @Vector(4, u32) = @splat(0xdeadbeef);
    _ = &x;
    const y: @Vector(4, u16) = @intCast(x);
    _ = y;
    return error.TestFailed;
}
// run
// backend=selfhosted,llvm
// target=x86_64-linux
