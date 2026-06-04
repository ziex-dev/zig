const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u16;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = if (builtin.abi.float() == .hard) 64 else 0;
    pub const div_by_zero: exception_t = if (builtin.abi.float() == .hard) 32 else 0;
    pub const overflow: exception_t = if (builtin.abi.float() == .hard) 16 else 0;
    pub const underflow: exception_t = if (builtin.abi.float() == .hard) 8 else 0;
    pub const inexact: exception_t = if (builtin.abi.float() == .hard) 4 else 0;
    pub const all_except: exception_t = if (builtin.abi.float() == .hard) 124 else 0;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = if (builtin.abi.float() == .hard) 3 else 0;
    pub const upward: exception_t = if (builtin.abi.float() == .hard) 2 else 0;
    pub const toward_zero: exception_t = if (builtin.abi.float() == .hard) 1 else 0;
};

pub const Env = extern struct {
    cw: u32 = 0,
};

inline fn cfc1_fcsr() exception_t {
    var val: u32 = 0;
    asm volatile (
        \\ cfc1 %[val], $31
        : [val] "=r" (val),
    );
    return @truncate(val);
}

inline fn ctc1_fcsr(val: exception_t) void {
    asm volatile (
        \\ ctc1 %[val], $31
        :
        : [val] "r" (@as(u32, val)),
    );
}

pub fn clearExcept(excepts: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fcsr = cfc1_fcsr();
    fcsr |= excepts & ExceptionFlag.all_except;
    fcsr ^= excepts & ExceptionFlag.all_except;
    ctc1_fcsr(fcsr);
}

pub fn raiseExcept(excepts: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;

    var fcsr = cfc1_fcsr();
    fcsr |= excepts & ExceptionFlag.all_except;
    ctc1_fcsr(fcsr);
}

pub fn testExcept(mask: exception_t) exception_t {
    if (comptime builtin.abi.float() == .soft) return ExceptionFlag.all_except;

    return cfc1_fcsr() & mask & ExceptionFlag.all_except;
}

pub fn getRound() exception_t {
    if (comptime builtin.abi.float() == .soft) return 0;
    return cfc1_fcsr() & 3;
}
pub fn setRound(mode: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = cfc1_fcsr();
    fcsr &= @as(exception_t, @bitCast(@as(i16, -4)));
    fcsr |= mode;
    ctc1_fcsr(fcsr);
}

pub fn getEnv() Env {
    var env: Env = .{};
    if (comptime builtin.abi.float() == .soft) return env;
    env.cw = @intCast(cfc1_fcsr());
    return env;
}

pub fn setEnv(env: Env) void {
    if (comptime builtin.abi.float() == .soft) return;
    ctc1_fcsr(@truncate(env.cw));
}
