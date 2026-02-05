const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.target.os.tag;

// Since this application entry contains an Init argument it will run
// initializations that are different from without Init argument.
pub fn main(_: std.process.Init) !void {
    if (native_os == .wasi or native_os == .windows) {
        return; // no signals
    }

    try test_user_assignable_signals_are_set_to_default_with_init();
}

/// The signals that are user assignable in POSIX.
const signals = [_]std.posix.SIG{
    .HUP,
    .INT,
    .QUIT,
    .TRAP,
    .ABRT,
    .SYS,

    // Currently being set by the init function in Threaded. The
    // effect is that if set in a parent process where it spawns a
    // child that happens to use an Init parameter in its main
    // function, it will instead be overwritten.
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

fn test_user_assignable_signals_are_set_to_default_with_init() !void {
    inline for (signals) |signal| {
        var sa: std.posix.Sigaction = undefined;

        std.posix.sigaction(signal, null, &sa);

        try std.testing.expectEqual(std.posix.SIG.DFL, sa.handler.handler);
    }
}
