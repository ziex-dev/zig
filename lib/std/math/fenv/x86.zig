const builtin = @import("builtin");
const std = @import("../../std.zig");

pub const exception_t = u16;

pub const ExceptionFlag = struct {
    pub const invalid: exception_t = 1;
    pub const denorm: exception_t = 2;
    pub const div_by_zero: exception_t = 4;
    pub const overflow: exception_t = 8;
    pub const underflow: exception_t = 16;
    pub const inexact: exception_t = 32;
    pub const all_except: exception_t = 63;
};

pub const RoundingMode = struct {
    pub const to_nearest: exception_t = 0;
    pub const downward: exception_t = 0x400;
    pub const upward: exception_t = 0x800;
    pub const toward_zero: exception_t = 0xc00;
};

pub const Env = extern struct {
    control_word: u16 = if (builtin.abi == .msvc) 0x027f else 0x037f,
    unused1: u16 = 0xFFFF, // unable to find a reason why this is not 0x0000
    status_word: u16 = 0x0000,
    unused2: u16 = 0xFFFF, // this as well
    tags: u16 = 0xffff,
    unused3: u16 = 0xFFFF, // this as well
    eip: u32 = 0x00000000,
    cs_selector: u16 = 0x0000,
    opcode_unused4: u16 = 0x0000,
    // opcode: u11 = 0b00000000000,
    // unused4: u5 = 0b00000,
    data_offset: u32 = 0x00000000,
    data_selector: u16 = 0x0000,
    unused5: u16 = 0xFFFF,
};

inline fn fnstsw() u16 {
    var val: u16 = 0;
    asm volatile (
        \\ fnstsw %[val]
        : [val] "=m" (val),
    );
    return val;
}
inline fn fnstcw() u16 {
    var val: u16 = 0;
    asm volatile (
        \\ fnstcw %[val]
        : [val] "=m" (val),
    );
    return val;
}
inline fn fldcw(val: u16) void {
    asm volatile (
        \\ movw %[val], -4(%%esp)
        \\ fldcw -4(%%esp)
        :
        : [val] "r" (val),
    );
}
inline fn fnclex() void {
    asm volatile (
        \\ fnclex
    );
}
inline fn stmxcsr() u32 {
    var val: u32 = 0;
    asm volatile (
        \\ stmxcsr %[val]
        : [val] "=m" (val),
    );
    return val;
}
inline fn ldmxcsr(val: u32) void {
    asm volatile (
        \\ movl %[val], -4(%%esp)
        \\ ldmxcsr -4(%%esp)
        :
        : [val] "r" (val),
    );
}

const sse = builtin.cpu.hasAny(builtin.target.cpu.arch.family(), &.{
    std.Target.x86.Feature.sse,
    std.Target.x86.Feature.sse2,
    std.Target.x86.Feature.sse3,
});

pub fn clearExcept(excepts: exception_t) void {
    var mask = excepts & ExceptionFlag.all_except;
    var fsw = fnstsw();

    if (comptime sse) {
        if (mask & fsw != 0) fnclex();

        var mxcsr = stmxcsr();
        fsw &= ExceptionFlag.all_except;
        mxcsr |= @as(u32, fsw);

        if (mxcsr & @as(u32, mask) == 0) return;
        mxcsr &= ~@as(u32, mask);
        ldmxcsr(mxcsr);
        return;
    }
    if (mask & fsw == 0) return;
    mask = ~mask;
    fsw &= mask;
    if (fsw & ExceptionFlag.all_except != 0) {
        fnclex();
        return;
    }

    asm volatile (
        \\ subl $32, %%esp
        \\ fnstenv (%esp)
        \\ mov %%al, 4(%%esp)
        \\ fldenv (%%esp)
        \\ addl $32, %%esp
        :
        : [fsw] "{al}" (fsw),
    );
}

pub fn raiseExcept(excepts: exception_t) void {
    asm volatile (
        \\ subl $32, %%esp
        \\ fnstenv (%%esp)
        \\ or %%al, 4(%%esp)
        \\ fldenv (%%esp)
        \\ addl $32, %%esp
        :
        : [ex] "{eax}" (excepts & ExceptionFlag.all_except),
    );
    if (comptime sse) {
        ldmxcsr(stmxcsr() | @as(u32, @intCast(excepts & ExceptionFlag.all_except)));
    }
}

pub fn testExcept(mask: exception_t) exception_t {
    var fsw = fnstsw();

    if (comptime sse) {
        fsw |= @truncate(stmxcsr());
    }
    fsw &= (mask & ExceptionFlag.all_except);
    return fsw;
}

pub fn getRound() exception_t {
    if (comptime sse) {
        return (@as(u16, @truncate(stmxcsr() >> 3)) & RoundingMode.toward_zero);
    } else {
        return (fnstcw() & RoundingMode.toward_zero);
    }
}
pub fn setRound(mode: exception_t) void {
    var fcw = fnstcw();
    fcw &= ~(RoundingMode.toward_zero);
    // fcw |= (mode & 0x11110000);
    fcw |= mode;
    fldcw(fcw);

    if (comptime sse) {
        var mxcsr = stmxcsr();
        mxcsr &= 0x9fff;
        // mxcsr |= (mode & 0b11110000);
        mxcsr |= (@as(u32, @intCast(mode)) << 3);
        ldmxcsr(mxcsr);
    }
}

pub fn getEnv() Env {
    var env: Env = .{};
    asm volatile (
        \\ fnstenv (%%eax)
        :
        : [addr] "{eax}" (&env),
        : .{ .memory = true });
    if (comptime sse) {
        env.status_word |= (@as(u16, @truncate(stmxcsr())) & ExceptionFlag.all_except);
    }
    return env;
}

pub fn setEnv(env: Env) void {
    asm volatile (
        \\ fldenv (%%ecx)
        :
        : [out] "{ecx}" (&env),
    );
    if (comptime sse) {
        asm volatile (
            \\ movl (%%ecx), %%ecx
            \\ andl $0xc00, %%ecx
            \\ shl $3, %%ecx
            \\ orl $0x1f80, %%ecx
            \\ mov %%ecx, -4(%%esp)
            \\ ldmxcsr -4(%%esp)
            :
            : [out] "{ecx}" (&env),
            : .{ .ecx = true });
    }
}
