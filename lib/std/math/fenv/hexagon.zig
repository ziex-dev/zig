const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = 2;
    pub const div_by_zero: exception_t = 4;
    pub const overflow: exception_t = 8;
    pub const underflow: exception_t = 16;
    pub const inexact: exception_t = 32;
    pub const all_except: exception_t = 62;
    const usr_fe_mask: exception_t = 0x3fc0003f;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = 2;
    pub const upward: exception_t = 3;
    pub const toward_zero: exception_t = 1;
};

pub const Env = extern struct {
    cw: u32 = 0,
};

inline fn getusr() exception_t {
    var val: exception_t = 0;
    asm volatile (
        \\ %[val] = usr
        : [val] "=r" (val),
    );
    return val;
}
inline fn setusr(val: exception_t) void {
    asm volatile (
        \\ usr = %[val]
        :
        : [val] "r" (val),
    );
}

pub fn clearExcept(excepts: exception_t) void {
    var fcsr = getusr();
    fcsr &= ~(excepts & ExceptionFlag.all_except);
    setusr(fcsr);
}

pub fn raiseExcept(excepts: exception_t) void {
    var fcsr = getusr();
    fcsr |= (excepts & ExceptionFlag.all_except);
    setusr(fcsr);
}

pub fn testExcept(mask: exception_t) exception_t {
    return (getusr() & mask & ExceptionFlag.all_except);
}

pub fn getRound() exception_t {
    return ((getusr() & (RoundingMode.upward << 22)) >> 22);
}
pub fn setRound(mode: exception_t) void {
    var fcsr = getusr();
    fcsr &= ~(RoundingMode.upward << 22);
    fcsr |= ((mode & RoundingMode.upward) << 22);
    setusr(fcsr);
}

pub fn getEnv() Env {
    var env: Env = .{};
    env.cw = getusr();
    return env;
}

pub fn setEnv(env: Env) void {
    var val = env.cw;
    val &= ExceptionFlag.usr_fe_mask;
    var fscr = getusr() & ~ExceptionFlag.usr_fe_mask;
    fscr |= val;
    setusr(fscr);
}
