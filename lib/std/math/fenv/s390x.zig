const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = 0x00800000;
    pub const div_by_zero: exception_t = 0x00400000;
    pub const overflow: exception_t = 0x00200000;
    pub const underflow: exception_t = 0x00100000;
    pub const inexact: exception_t = 0x00080000;
    pub const all_except: exception_t = 0x00f80000;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = 3;
    pub const upward: exception_t = 2;
    pub const toward_zero: exception_t = 1;
};

pub const Env = extern struct {
    cw: u32 = 0,
};

inline fn s390xGetFpc() exception_t {
    var fpc: exception_t = 0;
    asm volatile (
        \\ efpc %[out]
        : [out] "=r" (fpc),
    );
    return fpc;
}
inline fn s390xSetFpc(fpc: exception_t) void {
    asm volatile (
        \\ sfpc %[in]
        :
        : [in] "r" (fpc),
    );
}

pub fn clearExcept(excepts: exception_t) void {
    s390xSetFpc(s390xGetFpc() & ~(excepts & ExceptionFlag.all_except));
}

pub fn raiseExcept(excepts: exception_t) void {
    s390xSetFpc(s390xGetFpc() | (excepts & ExceptionFlag.all_except));
}

pub fn testExcept(mask: exception_t) exception_t {
    return s390xGetFpc() & mask & ExceptionFlag.all_except;
}

pub fn getRound() exception_t {
    return (s390xGetFpc() & 3);
}
pub fn setRound(mode: exception_t) void {
    s390xSetFpc(s390xGetFpc() & ~@as(u32, 3) | mode);
}

pub fn getEnv() Env {
    var env: Env = .{};
    env.cw = s390xGetFpc();
    return env;
}

pub fn setEnv(env: Env) void {
    s390xSetFpc(env.cw);
}
