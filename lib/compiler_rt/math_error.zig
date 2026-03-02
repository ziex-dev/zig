//! Helper functions for raising IEEE 754 floating-point exceptions.
//!
//! All functions are marked `noinline` so that LLVM cannot constant-fold the
//! exception-raising FP operations when it has branch-derived value-range
//! information about the caller's arguments.  For example, inside the negative
//! branch of logf, LLVM knows x < 0, so it can fold (x-x)/(x-x) -> 0.0/0.0 ->
//! NaN without emitting an fdiv instruction, which means no INVALID flag is set
//! in MXCSR.  Placing the operation inside a noinline function severs that
//! connection: the parameter is opaque to LLVM when it compiles the callee.

const std = @import("std");
const builtin = @import("builtin");

/// Sign of the infinity returned by fp_divzero_* functions.
/// Used to specify whether the result should be +Inf or -Inf.
pub const InfinitySign = enum { negative, positive };

// ---------------------------------------------------------------------------
// INVALID — raises the IEEE 754 INVALID exception and returns a quiet NaN.
// noinline: inside the function, x is an unknown f32, so LLVM cannot prove
//   x - x == 0.0 (x might be NaN), and thus cannot fold (x-x)/(x-x) to NaN
//   without emitting the fdiv instruction.
// volatile: additional barrier to prevent constant folding on aarch64
// ---------------------------------------------------------------------------
pub noinline fn fp_invalid_f32(x: f32) f32 {
    var result: f32 = x - x;
    const result_ptr: *volatile f32 = &result;
    return result_ptr.* / result_ptr.*;
}

pub noinline fn fp_invalid_f64(x: f64) f64 {
    var result: f64 = x - x;
    const result_ptr: *volatile f64 = &result;
    return result_ptr.* / result_ptr.*;
}

// ---------------------------------------------------------------------------
// DIVBYZERO — raises the IEEE 754 DIVBYZERO exception and returns ±Inf.
// sign=.negative → -Inf  (used by log(0) → -∞)
// sign=.positive → +Inf
//
// A volatile read prevents LLVM from substituting the compile-time constant
// value ±1.0 before emitting the fdiv instruction.
// ---------------------------------------------------------------------------
pub noinline fn fp_divzero_f32(sign: InfinitySign) f32 {
    var v: f32 = if (sign == .negative) -1.0 else 1.0;
    const vp: *volatile f32 = &v;
    return vp.* / 0.0;
}

pub noinline fn fp_divzero_f64(sign: InfinitySign) f64 {
    var v: f64 = if (sign == .negative) -1.0 else 1.0;
    const vp: *volatile f64 = &v;
    return vp.* / 0.0;
}

// ---------------------------------------------------------------------------
// OVERFLOW — raises OVERFLOW|INEXACT and returns +Inf.
// noinline: x is unknown inside the function, so LLVM cannot fold x * huge
//   to infinity without emitting the fmul instruction.
// volatile: additional barrier to prevent constant folding on aarch64
// ---------------------------------------------------------------------------
pub noinline fn fp_overflow_f32(x: f32) f32 {
    var huge: f32 = 0x1.0p127;
    const huge_ptr: *volatile f32 = &huge;
    return x * huge_ptr.*;
}

pub noinline fn fp_overflow_f64(x: f64) f64 {
    var huge: f64 = 0x1p1023;
    const huge_ptr: *volatile f64 = &huge;
    return x * huge_ptr.*;
}

// ---------------------------------------------------------------------------
// UNDERFLOW — raises UNDERFLOW|INEXACT as a side effect (result is discarded).
// noinline: x is unknown inside the function, so LLVM cannot fold -tiny/x to
//   zero without emitting the fdiv instruction.
// volatile: additional barrier to prevent constant folding on aarch64
// doNotOptimizeAway: prevents LLVM from eliminating the division as dead code.
// ---------------------------------------------------------------------------
pub noinline fn fp_underflow_f32(x: f32) void {
    var tiny: f32 = -0x1.0p-149;
    const tiny_ptr: *volatile f32 = &tiny;
    std.mem.doNotOptimizeAway(tiny_ptr.* / x);
}

pub noinline fn fp_underflow_f64(x: f64) void {
    var tiny: f64 = -0x0.0000000000001p-1022;
    const tiny_ptr: *volatile f64 = &tiny;
    std.mem.doNotOptimizeAway(tiny_ptr.* / x);
}

// ---------------------------------------------------------------------------
// FP exception flag helpers — inline assembly, no libc required.
// Supported on x86_64 (MXCSR) and aarch64 (FPSR).
// ---------------------------------------------------------------------------

// MXCSR / FPSR status-flag bit positions.
pub const FE_INVALID: u32 = switch (builtin.cpu.arch) {
    .x86_64 => 1 << 0, // IE
    .aarch64 => 1 << 0, // IOC
    else => 0,
};
pub const FE_DIVBYZERO: u32 = switch (builtin.cpu.arch) {
    .x86_64 => 1 << 2, // ZE
    .aarch64 => 1 << 1, // DZC
    else => 0,
};
pub const FE_OVERFLOW: u32 = switch (builtin.cpu.arch) {
    .x86_64 => 1 << 3, // OE
    .aarch64 => 1 << 2, // OFC
    else => 0,
};
pub const FE_UNDERFLOW: u32 = switch (builtin.cpu.arch) {
    .x86_64 => 1 << 4, // UE
    .aarch64 => 1 << 3, // UFC
    else => 0,
};

/// Read the current FP exception status flags (MXCSR status bits on x86_64,
/// FPSR on aarch64).
pub inline fn getFpStatus() u32 {
    return switch (builtin.cpu.arch) {
        .x86_64 => blk: {
            var mxcsr: u32 = 0;
            asm volatile ("stmxcsr %[v]"
                : [v] "=m" (mxcsr),
                :
                : "memory");
            break :blk mxcsr & 0x3f; // low 6 bits are status flags
        },
        .aarch64 => blk: {
            var fpsr: u64 = 0;
            asm volatile ("mrs %[v], fpsr"
                : [v] "=r" (fpsr),
                :
                : "memory");
            break :blk @as(u32, @truncate(fpsr & 0x1f)); // low 5 bits
        },
        else => 0,
    };
}

/// Clear all FP exception status flags.
pub inline fn clearFpStatus() void {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            var mxcsr: u32 = 0;
            asm volatile ("stmxcsr %[v]"
                : [v] "=m" (mxcsr),
                :
                : "memory");
            mxcsr &= ~@as(u32, 0x3f);
            asm volatile ("ldmxcsr %[v]"
                :
                : [v] "m" (mxcsr),
                : "memory");
        },
        .aarch64 => {
            // Read-modify-write: preserve QC (bit 27) and condition flags (bits 28-31),
            // clear only the five exception status bits (bits 0-4: IOC/DZC/OFC/UFC/IXC).
            var fpsr: u64 = 0;
            asm volatile ("mrs %[v], fpsr"
                : [v] "=r" (fpsr),
                :
                : "memory");
            fpsr &= ~@as(u64, 0x1f);
            asm volatile ("msr fpsr, %[v]"
                :
                : [v] "r" (fpsr),
                : "memory");

            // Disable exception trapping in FPCR (bits 0-4: EIE/EZE/EOE/EUE/EIXE).
            // These bits ENABLE EXCEPTION TRAPS (raising exceptions), not flag setting.
            // To only set flags without trapping, these bits must be DISABLED.
            var fpcr: u64 = 0;
            asm volatile ("mrs %[v], fpcr"
                : [v] "=r" (fpcr),
                :
                : "memory");
            fpcr &= ~@as(u64, 0x1f); // Disable bits 0-4 (exception trap enable flags)
            asm volatile ("msr fpcr, %[v]"
                :
                : [v] "r" (fpcr),
                : "memory");
        },
        else => {},
    }
}

test "fp_invalid raises INVALID" {
    if (FE_INVALID == 0) return error.SkipZigTest;

    clearFpStatus();
    const nan_f32 = fp_invalid_f32(1.0);
    try std.testing.expect(std.math.isNan(nan_f32));
    try std.testing.expect(getFpStatus() & FE_INVALID != 0);

    clearFpStatus();
    const nan_f64 = fp_invalid_f64(1.0);
    try std.testing.expect(std.math.isNan(nan_f64));
    try std.testing.expect(getFpStatus() & FE_INVALID != 0);
}

test "fp_divzero raises DIVBYZERO" {
    if (FE_DIVBYZERO == 0) return error.SkipZigTest;

    clearFpStatus();
    const neg_inf_f32 = fp_divzero_f32(.negative);
    try std.testing.expectEqual(neg_inf_f32, -std.math.inf(f32));
    try std.testing.expect(getFpStatus() & FE_DIVBYZERO != 0);

    clearFpStatus();
    const pos_inf_f32 = fp_divzero_f32(.positive);
    try std.testing.expectEqual(pos_inf_f32, std.math.inf(f32));
    try std.testing.expect(getFpStatus() & FE_DIVBYZERO != 0);

    clearFpStatus();
    const neg_inf_f64 = fp_divzero_f64(.negative);
    try std.testing.expectEqual(neg_inf_f64, -std.math.inf(f64));
    try std.testing.expect(getFpStatus() & FE_DIVBYZERO != 0);

    clearFpStatus();
    const pos_inf_f64 = fp_divzero_f64(.positive);
    try std.testing.expectEqual(pos_inf_f64, std.math.inf(f64));
    try std.testing.expect(getFpStatus() & FE_DIVBYZERO != 0);
}

test "fp_overflow raises OVERFLOW" {
    if (FE_OVERFLOW == 0) return error.SkipZigTest;

    clearFpStatus();
    std.mem.doNotOptimizeAway(fp_overflow_f32(std.math.floatMax(f32)));
    try std.testing.expect(getFpStatus() & FE_OVERFLOW != 0);

    clearFpStatus();
    std.mem.doNotOptimizeAway(fp_overflow_f64(std.math.floatMax(f64)));
    try std.testing.expect(getFpStatus() & FE_OVERFLOW != 0);
}

test "fp_underflow raises UNDERFLOW" {
    if (FE_UNDERFLOW == 0) return error.SkipZigTest;

    clearFpStatus();
    fp_underflow_f32(-100.0);
    try std.testing.expect(getFpStatus() & FE_UNDERFLOW != 0);

    clearFpStatus();
    fp_underflow_f64(-800.0);
    try std.testing.expect(getFpStatus() & FE_UNDERFLOW != 0);
}
