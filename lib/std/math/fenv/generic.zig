const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = 0;
    pub const div_by_zero: exception_t = 0;
    pub const overflow: exception_t = 0;
    pub const underflow: exception_t = 0;
    pub const inexact: exception_t = 0;
    pub const all_except: exception_t = 0;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = 0;
    pub const upward: exception_t = 0;
    pub const toward_zero: exception_t = 0;
};

pub const Env = extern struct {
    cw: u32 = 0,
};

pub fn clearExcept(excepts: exception_t) void {
    _ = excepts;
    return;
}

pub fn raiseExcept(excepts: exception_t) void {
    _ = excepts;
    return;
}

pub fn testExcept(mask: exception_t) exception_t {
    _ = mask;
    return ExceptionFlag.all_except;
}

pub fn getRound() exception_t {
    return 0;
}
pub fn setRound(mode: exception_t) void {
    _ = mode;
}

pub fn getEnv() Env {
    return .{};
}

pub fn setEnv(env: Env) void {
    _ = env;
}
