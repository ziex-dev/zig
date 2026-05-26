const std = @import("std");
pub fn panic(message: []const u8, _: ?*std.lang.StackTrace, _: ?usize) noreturn {
    if (std.mem.eql(u8, message, "integer does not fit in destination type")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
pub fn main() !void {
    var value: c_short = -1;
    _ = &value;
    const casted: u32 = @intCast(value);
    _ = casted;
    return error.TestFailed;
}
// run
// backend=selfhosted,llvm
// target=x86_64-linux
