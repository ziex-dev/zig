const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = 1;
    pub const div_by_zero: exception_t = 2;
    pub const overflow: exception_t = 4;
    pub const underflow: exception_t = 8;
    pub const inexact: exception_t = 16;
    pub const all_except: exception_t = 31;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = 0x00800000;
    pub const upward: exception_t = 0x00400000;
    pub const toward_zero: exception_t = 0x00c00000;
};

pub const Env = extern struct {
    fpcr: u32 = 0,
    fpsr: u32 = 0,
};

inline fn get_fpcr() exception_t {
    var val: u32 = 0;
    asm volatile (
        \\ mrs %[val], fpcr
        : [val] "=r" (val),
    );
    return val;
}
inline fn get_fpsr() exception_t {
    var val: u32 = 0;
    asm volatile (
        \\ mrs %[val], fpsr
        : [val] "=r" (val),
    );
    return val;
}
inline fn set_fpsr(val: exception_t) void {
    asm volatile (
        \\ msr fpsr, %[val]
        :
        : [val] "r" (val),
    );
}
inline fn set_fpcr(val: exception_t) void {
    asm volatile (
        \\ msr fpcr, %[val]
        :
        : [val] "r" (val),
    );
}

pub fn clearExcept(excepts: exception_t) void {
    var fpsr = get_fpsr();
    fpsr &= ~(excepts & ExceptionFlag.all_except);
    set_fpsr(fpsr);
}

pub fn raiseExcept(excepts: exception_t) void {
    var fpsr = get_fpsr();
    fpsr |= (excepts & ExceptionFlag.all_except);
    set_fpsr(fpsr);
}

pub fn testExcept(mask: exception_t) exception_t {
    return get_fpsr() & (mask & ExceptionFlag.all_except);
}

pub fn getRound() exception_t {
    return get_fpcr() & RoundingMode.toward_zero;
}
pub fn setRound(mode: exception_t) void {
    var fpcr = get_fpcr();
    fpcr &= ~RoundingMode.toward_zero;
    fpcr |= mode;
    set_fpcr(fpcr);
}

pub fn getEnv() Env {
    var env: Env = .{};
    env.fpcr = get_fpcr();
    env.fpsr = get_fpsr();
    return env;
}

pub fn setEnv(env: Env) void {
    set_fpcr(env.fpcr);
    set_fpsr(env.fpsr);
}
