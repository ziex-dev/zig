const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.target.os.tag;

pub fn main() !void {
    if (native_os == .wasi or native_os == .windows) {
        return; // no sigaction
    }

    try test_user_assignable_signals_are_set_to_default();
}

/// The signals that are user assignable in POSIX.
const signals = [_]std.posix.SIG{
    .HUP,
    .INT,
    .QUIT,
    .TRAP,
    .ABRT,
    .SYS,
    .PIPE,
    .ALRM,
    .TERM,
    .TSTP,
    .CONT,
    .CHLD,
    .TTIN,
    .TTOU,
    .IO,
    .XCPU,
    .XFSZ,
    .VTALRM,
    .PROF,
    .WINCH,
    .USR1,
    .USR2,
};

fn test_user_assignable_signals_are_set_to_default() !void {
    inline for (signals) |signal| {
        var sa: std.posix.Sigaction = undefined;

        std.posix.sigaction(signal, null, &sa);

        try std.testing.expectEqual(std.posix.SIG.DFL, sa.handler.handler);
    }
}
