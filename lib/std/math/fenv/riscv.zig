const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = 16;
    pub const div_by_zero: exception_t = 8;
    pub const overflow: exception_t = 4;
    pub const underflow: exception_t = 2;
    pub const inexact: exception_t = 1;
    pub const all_except: exception_t = 31;
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

pub fn clearExcept(excepts: exception_t) void {
    asm volatile (
        \\ csrc fflags, %[mask]
        :
        : [mask] "r" (excepts),
        : .{
          .fflags = true,
        });
}

pub fn raiseExcept(excepts: exception_t) void {
    asm volatile (
        \\ csrs fflags, %[mask]
        :
        : [mask] "r" (excepts),
        : .{ .fflags = true });
}

pub fn testExcept(mask: exception_t) exception_t {
    var out: exception_t = 0;
    asm volatile (
        \\ frflags %[out]
        : [out] "=r" (out),
    );
    return (out & mask);
}

pub fn getRound() exception_t {
    var out: exception_t = 0;
    asm volatile (
        \\ frrm %[out]
        : [out] "=r" (out),
    );
    return out;
}
pub fn setRound(mode: exception_t) void {
    asm volatile (
        \\ fsrm %[in]
        :
        : [in] "r" (@as(u64, @intCast(mode))),
    );
}

pub fn getEnv() Env {
    var env: Env = .{};
    asm volatile (
        \\ frcsr t0
        \\ sw t0 , 0(t1)
        :
        : [addr] "{t1}" (&env),
        : .{ .memory = true });
    return env;
}

pub fn setEnv(env: Env) void {
    asm volatile (
        \\ lw t1, 0(%[addr])
        \\ fscsr t1
        :
        : [addr] "r" (&env),
    );
}
