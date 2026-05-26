const std = @import("std");
pub fn foo(message: []const u8, stack_trace: ?*std.lang.StackTrace) noreturn {
    @call(.always_tail, bar, .{ message, stack_trace });
}
pub fn bar(message: []const u8, stack_trace: ?*std.lang.StackTrace) noreturn {
    _ = message;
    _ = stack_trace;
    std.process.exit(0);
}

pub fn main() void {
    foo("foo", null);
}

// run
// backend=llvm
// target=x86_64-linux,x86_64-macos,aarch64-linux,aarch64-macos
