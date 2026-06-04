const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = if (builtin.abi.float() == .hard) 0x20000000 else 0;
    pub const div_by_zero: exception_t = if (builtin.abi.float() == .hard) 0x04000000 else 0;
    pub const overflow: exception_t = if (builtin.abi.float() == .hard) 0x10000000 else 0;
    pub const underflow: exception_t = if (builtin.abi.float() == .hard) 0x08000000 else 0;
    pub const inexact: exception_t = if (builtin.abi.float() == .hard) 0x02000000 else 0;
    pub const all_except: exception_t = if (builtin.abi.float() == .hard) 0x3e080000 else 0;
    const all_invalid: exception_t = if (builtin.abi.float() == .hard) 0x01f80700 else 0;
    const software_invalid: exception_t = if (builtin.abi.float() == .hard) 0x00000400 else 0;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = if (builtin.abi.float() == .hard) 3 else 0;
    pub const upward: exception_t = if (builtin.abi.float() == .hard) 2 else 0;
    pub const toward_zero: exception_t = if (builtin.abi.float() == .hard) 1 else 0;
};

pub const Env = extern struct {
    cw: f64 = 0,
};

inline fn mffs() u32 {
    var val: f64 = 0;
    asm volatile (
        \\ mffs %[val]
        : [val] "=d" (val),
    );
    return @truncate(@as(u64, @bitCast(val)));
}
inline fn mtfsf(val: u32) void {
    asm volatile (
        \\ mtfsf 255, %[val]
        :
        : [val] "d" (@as(u64, val)),
    );
}

pub fn clearExcept(excepts: exception_t) void {
    if (builtin.abi.float() == .soft) return;

    var mask = excepts & ExceptionFlag.all_except;
    if (mask & ExceptionFlag.invalid != 0) mask |= ExceptionFlag.all_invalid;

    var fpscr = mffs();
    fpscr &= ~mask;
    mtfsf(fpscr);
}

pub fn raiseExcept(excepts: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var mask = excepts & ExceptionFlag.all_except;
    if (mask & ExceptionFlag.invalid != 0) mask |= ExceptionFlag.software_invalid;

    var fpscr = mffs();
    fpscr |= mask;
    mtfsf(fpscr);
}

pub fn testExcept(mask: exception_t) exception_t {
    if (comptime builtin.abi.float() == .soft) return ExceptionFlag.all_except;
    const fpscr = mffs();
    return fpscr & mask & ExceptionFlag.all_except;
}

pub fn getRound() exception_t {
    if (comptime builtin.abi.float() == .soft) return ExceptionFlag.all_except;

    return mffs() & RoundingMode.downward;
}
pub fn setRound(mode: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fpscr = mffs();
    fpscr &= ~RoundingMode.downward;
    fpscr |= mode;
    mtfsf(fpscr);
}

pub fn getEnv() Env {
    var env: Env = .{};
    if (comptime builtin.abi.float() == .soft) return env;

    env.cw = @bitCast(@as(u64, mffs()));
    return env;
}

pub fn setEnv(env: Env) void {
    if (comptime builtin.abi.float() == .soft) return;

    mtfsf(@truncate(@as(u64, @bitCast(env.cw))));
}
