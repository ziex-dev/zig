const builtin = @import("builtin");
const std = @import("../std.zig");

const impl = switch (builtin.cpu.arch) {
    .x86_64 => @import("fenv/x86_64.zig"),
    .s390x => @import("fenv/s390x.zig"),
    .riscv64, .riscv32 => @import("fenv/riscv.zig"),
    .powerpc64, .powerpc64le => @import("fenv/powerpc64.zig"),
    .powerpc, .powerpcle => @import("fenv/powerpc.zig"),
    // .powerpcle => @import("fenv/powerpcle.zig"),
    .mips64, .mips64el, .mips, .mipsel => @import("fenv/mips.zig"),
    .m68k => @import("fenv/m68k.zig"),
    .loongarch64 => @import("fenv/loongarch64.zig"),
    .x86 => @import("fenv/x86.zig"),
    .hexagon => @import("fenv/hexagon.zig"),
    // .arm, .thumb => @import("fenv/arm.zig"),
    .aarch64, .aarch64_be => @import("fenv/aarch64.zig"),
    // .armeb, .thumbeb => @import("fenv/generic.zig"),
    else => @import("fenv/generic.zig"),
};

pub const exception_t = impl.exception_t;
pub const ExceptionFlag = impl.ExceptionFlag;
pub const RoundingMode = impl.RoundingMode;
pub const Env = impl.Env;

pub const clearExcept = impl.clearExcept;
pub const raiseExcept = impl.raiseExcept;
pub const testExcept = impl.testExcept;
pub fn getExceptFlag(mask: exception_t) exception_t {
    return testExcept(mask);
}
pub fn setExceptFlag(excepts: exception_t, mask: exception_t) void {
    clearExcept(excepts);
    raiseExcept(excepts & mask);
}
pub fn holdExcept() Env {
    const env = getEnv();
    clearExcept(ExceptionFlag.all_except);
    return env;
}

pub const getRound = impl.getRound;
pub const setRound = impl.setRound;

pub const getEnv = impl.getEnv;
pub const setEnv = impl.setEnv;
pub fn updateEnv(env: Env) void {
    const ex = testExcept(ExceptionFlag.all_except);
    setEnv(env);
    raiseExcept(ex);
}

test "fenv rounding" {
    setRound(RoundingMode.downward);
    try std.testing.expectEqual(RoundingMode.downward, getRound());
    setRound(RoundingMode.toward_zero);
    try std.testing.expectEqual(RoundingMode.toward_zero, getRound());
    setRound(RoundingMode.to_nearest);
    try std.testing.expectEqual(RoundingMode.to_nearest, getRound());
    setRound(RoundingMode.upward);
    try std.testing.expectEqual(RoundingMode.upward, getRound());

    const two100: f32 = 0x1p100;
    const env = getEnv();
    const g = getRound();

    setEnv(.{});
    try std.testing.expectEqual(RoundingMode.to_nearest, getRound());
    try std.testing.expectEqual(two100, two100 + 1);
    try std.testing.expectEqual(two100, two100 - 1);

    setEnv(env);
    try std.testing.expectEqual(g, getRound());
}

test "fenv except" {
    clearExcept(ExceptionFlag.all_except);
    raiseExcept(ExceptionFlag.div_by_zero);
    try std.testing.expectEqual(ExceptionFlag.div_by_zero, testExcept(ExceptionFlag.all_except));

    clearExcept(ExceptionFlag.all_except);
    raiseExcept(ExceptionFlag.inexact);
    try std.testing.expectEqual(ExceptionFlag.inexact, testExcept(ExceptionFlag.all_except));

    clearExcept(ExceptionFlag.all_except);
    raiseExcept(ExceptionFlag.invalid);
    try std.testing.expectEqual(ExceptionFlag.invalid, testExcept(ExceptionFlag.all_except));

    clearExcept(ExceptionFlag.all_except);
    raiseExcept(ExceptionFlag.underflow);
    var res = testExcept(ExceptionFlag.all_except);
    if (res != ExceptionFlag.underflow) {
        try std.testing.expectEqual(ExceptionFlag.underflow | ExceptionFlag.inexact, res);
    }

    clearExcept(ExceptionFlag.all_except);
    raiseExcept(ExceptionFlag.overflow);
    res = testExcept(ExceptionFlag.all_except);
    if (res != ExceptionFlag.overflow) {
        try std.testing.expectEqual(ExceptionFlag.overflow | ExceptionFlag.inexact, res);
    }

    var env: Env = .{};

    raiseExcept(ExceptionFlag.all_except);
    env = getEnv();
    try std.testing.expectEqual(ExceptionFlag.all_except, testExcept(ExceptionFlag.all_except));

    setEnv(.{});
    try std.testing.expectEqual(0, testExcept(ExceptionFlag.all_except));

    setEnv(env);
    try std.testing.expectEqual(ExceptionFlag.all_except, testExcept(ExceptionFlag.all_except));
}
