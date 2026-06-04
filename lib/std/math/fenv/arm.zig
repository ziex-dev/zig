const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u64;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = if (builtin.abi.float() == .hard) 1 else 0;
    pub const div_by_zero: exception_t = if (builtin.abi.float() == .hard) 2 else 0;
    pub const overflow: exception_t = if (builtin.abi.float() == .hard) 4 else 0;
    pub const underflow: exception_t = if (builtin.abi.float() == .hard) 8 else 0;
    pub const inexact: exception_t = if (builtin.abi.float() == .hard) 16 else 0;
    pub const all_except: exception_t = if (builtin.abi.float() == .hard) 31 else 0;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = if (builtin.abi.float() == .hard) 0x00800000 else 0;
    pub const upward: exception_t = if (builtin.abi.float() == .hard) 0x00400000 else 0;
    pub const toward_zero: exception_t = if (builtin.abi.float() == .hard) 0x00c00000 else 0;
};

pub const Env = extern struct {
    cw: u64 = 0,
};

inline fn vmrs() exception_t {
    var val: exception_t = 0;
    asm volatile (
        \\ vmrs %[val], fpscr
        : [val] "=r" (val),
    );
    return val;
}

inline fn vmsr(val: exception_t) void {
    asm volatile (
        \\ vmsr fpscr, %[val]
        :
        : [val] "r" (val),
    );
}

pub fn clearExcept(excepts: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fcsr = vmrs();
    fcsr &= ~(excepts & ExceptionFlag.all_except);
    vmsr(fcsr);
}

pub fn raiseExcept(excepts: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fcsr = vmrs();
    fcsr |= (excepts & ExceptionFlag.all_except);
    vmsr(fcsr);
}

pub fn testExcept(mask: exception_t) exception_t {
    if (comptime builtin.abi.float() == .soft) return ExceptionFlag.all_except;

    return vmrs() & (mask & ExceptionFlag.all_except);
}

pub fn getRound() exception_t {
    if (comptime builtin.abi.float() == .soft) return 0;
    return vmrs() & RoundingMode.toward_zero;
}
pub fn setRound(mode: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = vmrs();
    fcsr &= ~RoundingMode.toward_zero;
    fcsr |= mode;
    vmsr(fcsr);
}

pub fn getEnv() Env {
    var env: Env = .{};
    if (comptime builtin.abi.float() == .soft) return env;
    env.cw = vmrs();
    return env;
}

pub fn setEnv(env: Env) void {
    if (comptime builtin.abi.float() == .soft) return;
    vmsr(env.cw);
}
