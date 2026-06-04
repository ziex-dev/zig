const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = 0x20000000;
    pub const div_by_zero: exception_t = 0x04000000;
    pub const overflow: exception_t = 0x10000000;
    pub const underflow: exception_t = 0x08000000;
    pub const inexact: exception_t = 0x02000000;
    pub const all_except: exception_t = 0x3e080000;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = 3;
    pub const upward: exception_t = 2;
    pub const toward_zero: exception_t = 1;
};

pub const Env = extern struct {
    cw: f64 = 0,
};

inline fn powerpc64GetFpscr() exception_t {
    return @truncate(@as(u64, @bitCast(powerpc64GetFpscr_f())));
}
inline fn powerpc64GetFpscr_f() f64 {
    var fpc: f64 = 0;
    asm volatile (
        \\ mffs %[out]
        : [out] "=d" (fpc),
    );
    return fpc;
}
inline fn powerpc64SetFpscr(fpc: exception_t) void {
    powerpc64SetFpscr_f(@bitCast(@as(u64, @intCast(fpc))));
}
inline fn powerpc64SetFpscr_f(fpc: f64) void {
    asm volatile (
        \\ mtfsf 255, %[out]
        :
        : [out] "d" (fpc),
    );
}

pub fn clearExcept(excepts: exception_t) void {
    var mask = excepts & ExceptionFlag.all_except;
    if ((mask & ExceptionFlag.invalid) != 0) mask |= 0x1f80700;
    powerpc64SetFpscr(powerpc64GetFpscr() & ~mask);
}

pub fn raiseExcept(excepts: exception_t) void {
    var mask = excepts & ExceptionFlag.all_except;
    if ((mask & ExceptionFlag.invalid) != 0) mask |= 0x00000400;
    powerpc64SetFpscr(powerpc64GetFpscr() | mask);
}

pub fn testExcept(mask: exception_t) exception_t {
    return powerpc64GetFpscr() & mask & ExceptionFlag.all_except;
}

pub fn getRound() exception_t {
    return (powerpc64GetFpscr() & 3);
}
pub fn setRound(mode: exception_t) void {
    powerpc64SetFpscr(powerpc64GetFpscr() & ~@as(u32, @intCast(3)) | mode);
}

pub fn getEnv() Env {
    var env: Env = .{};
    env.cw = powerpc64GetFpscr_f();
    return env;
}

pub fn setEnv(env: Env) void {
    powerpc64SetFpscr_f(env.cw);
}
