const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = if (builtin.abi.float() == .hard) 0x100000 else 0;
    pub const div_by_zero: exception_t = if (builtin.abi.float() == .hard) 0x080000 else 0;
    pub const overflow: exception_t = if (builtin.abi.float() == .hard) 0x040000 else 0;
    pub const underflow: exception_t = if (builtin.abi.float() == .hard) 0x020000 else 0;
    pub const inexact: exception_t = if (builtin.abi.float() == .hard) 0x010000 else 0;
    pub const all_except: exception_t = if (builtin.abi.float() == .hard) 0x1f0000 else 0;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = if (builtin.abi.float() == .hard) 0x300 else 0;
    pub const upward: exception_t = if (builtin.abi.float() == .hard) 0x200 else 0;
    pub const toward_zero: exception_t = if (builtin.abi.float() == .hard) 0x100 else 0;
};

pub const Env = extern struct {
    cw: u32 = 0,
};
inline fn movfcsr2gr() exception_t {
    var val: u64 = 0;
    asm volatile (
        \\ movfcsr2gr %[val], $fcsr0
        : [val] "=r" (val),
    );
    return @truncate(val);
}
inline fn movgr2fcsr(val: exception_t) void {
    asm volatile (
        \\ movgr2fcsr $fcsr0, %[val]
        :
        : [val] "r" (val),
        : .{ .fcsr0 = true });
}

pub fn clearExcept(excepts: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = movfcsr2gr();
    fcsr &= ~(excepts & ExceptionFlag.all_except);
    movgr2fcsr(fcsr);
}

pub fn raiseExcept(excepts: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = movfcsr2gr();
    fcsr |= (excepts & ExceptionFlag.all_except);
    movgr2fcsr(fcsr);
}

pub fn testExcept(mask: exception_t) exception_t {
    if (comptime builtin.abi.float() == .soft) return ExceptionFlag.all_except;
    return (movfcsr2gr() & mask & ExceptionFlag.all_except);
}

pub fn getRound() exception_t {
    if (comptime builtin.abi.float() == .soft) return RoundingMode.to_nearest;
    return (movfcsr2gr() & RoundingMode.downward);
}
pub fn setRound(mode: exception_t) void {
    if (comptime builtin.abi.float() == .soft) return;
    var fcsr = movfcsr2gr();
    fcsr &= RoundingMode.downward;
    fcsr &= ~RoundingMode.downward;
    fcsr |= (mode & RoundingMode.downward);
    movgr2fcsr(fcsr);
}

pub fn getEnv() Env {
    var env: Env = .{};
    if (comptime builtin.abi.float() == .soft) return env;
    env.cw = movfcsr2gr();
    return env;
}

pub fn setEnv(env: Env) void {
    if (comptime builtin.abi.float() == .soft) return;
    movgr2fcsr(env.cw);
}
