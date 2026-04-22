const std = @import("std");

pub fn main() !void {
    var x: u32 = 300;
    _ = &x;
    var y: u8 = @intCast(x);
    _ = &y;
}
