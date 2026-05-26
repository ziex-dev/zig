const std = @import("std");

pub fn panic(message: []const u8, _: ?*std.lang.StackTrace, _: ?usize) noreturn {
    if (std.mem.eql(u8, message, "switch on corrupt value")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}

const E = enum(u32) {
    one = 1,
    two = 2,
};

pub fn main() !void {
    var a: E = undefined;
    @as(*u32, @ptrCast(&a)).* = 255;
    switch (a) {
        .one => @panic("one"),
        else => @panic("else"),
    }
}
// run
// backend=selfhosted,llvm
// target=x86_64-linux
