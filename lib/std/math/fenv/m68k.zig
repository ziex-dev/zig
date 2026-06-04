const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u32;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t =
        if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 128 else 0;
    pub const div_by_zero: exception_t = if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 16 else 0;
    pub const overflow: exception_t = if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 64 else 0;
    pub const underflow: exception_t = if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 32 else 0;
    pub const inexact: exception_t = if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 8 else 0;
    pub const all_except: exception_t = if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 0xf8 else 0;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 32 else 0;
    pub const upward: exception_t = if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 48 else 0;
    pub const toward_zero: exception_t = if (builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) 16 else 0;
};

pub const Env = extern struct {
    control_register: u32 = 0,
    status_register: u32 = 0,
    instruction_address: u32 = 0,
};

inline fn m68kGetSR() exception_t {
    var v: exception_t = 0;
    asm volatile (
        \\ fmove.l %%fpsr, %[out]
        : [out] "=dm" (v),
    );
    return v;
}
inline fn m68kSetSR(v: exception_t) void {
    asm volatile (
        \\ fmove.l %[v], %%fpsr)
        :
        : [v] "dm" (v),
    );
}
inline fn m68kGetCR() exception_t {
    var v: exception_t = 0;
    asm volatile (
        \\ fmove.l %%fpcr, %[out]
        : [out] "=dm" (v),
    );
    return v;
}
inline fn m68kSetCR(v: exception_t) void {
    asm volatile (
        \\ fmove.l %[v], %%fpcr
        :
        : [v] "dm" (v),
    );
}

pub fn clearExcept(excepts: exception_t) void {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        if (excepts & ~ExceptionFlag.all_except != 0) return;
        m68kSetSR(m68kGetSR() & ~excepts);
    }
}

pub fn raiseExcept(excepts: exception_t) void {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        if (excepts & ~ExceptionFlag.all_except) return;
        m68kSetSR(m68kGetSR() | excepts);
    }
}

pub fn testExcept(mask: exception_t) exception_t {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        return m68kGetSR() & mask;
    }
    return ExceptionFlag.all_except;
}

pub fn getRound() exception_t {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        return m68kGetCR() & RoundingMode.upward;
    }
    return RoundingMode.to_nearest;
}
pub fn setRound(mode: exception_t) void {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        m68kSetCR((m68kGetCR() & ~RoundingMode.upward) | mode);
    }
}

pub fn getEnv() Env {
    var env: Env = .{};
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        env.control_register = m68kGetCR();
        env.status_register = m68kGetSR();

        var iaddr: u32 = 0;
        asm volatile (
            \\ fmove.l %%fpiar, %[out]
            : [out] "=dm" (iaddr),
        );

        env.instruction_address = iaddr;
    }
    return env;
}

pub fn setEnv(env: Env) void {
    if (comptime builtin.target.cpu.features.isEnabled(@intFromEnum(std.Target.m68k.Feature.isa_68881))) {
        m68kSetCR(env.control_register);
        m68kSetSR(env.status_register);

        asm volatile (
            \\ fmove.l  %[in], %%fpiar
            :
            : [in] "dm" (env.instruction_address),
        );
    }
}
