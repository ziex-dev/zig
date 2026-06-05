//! Ported from musl, which is MIT licensed.
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/truncf.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/trunc.c

const std = @import("std");
const math = std.math;
const mem = std.mem;
const expect = std.testing.expect;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__trunch, "__trunch");
    symbol(&truncf, "truncf");
    symbol(&trunc, "trunc");
    symbol(&__truncx, "__truncx");
    if (compiler_rt.want_ppc_abi) {
        symbol(&truncq, "truncf128");
    }
    symbol(&truncq, "truncq");
    symbol(&truncl, "truncl");
}

pub fn __trunch(x: f16) callconv(.c) f16 {
    return impl(f16, x);
}

pub fn truncf(x: f32) callconv(.c) f32 {
    return impl(f32, x);
}

pub fn trunc(x: f64) callconv(.c) f64 {
    return impl(f64, x);
}

pub fn __truncx(x: f80) callconv(.c) f80 {
    return impl(f80, x);
}

pub fn truncq(x: f128) callconv(.c) f128 {
    return impl(f128, x);
}

pub fn truncl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return trunc(x),
        80 => return __truncx(x),
        128 => return truncq(x),
        else => @compileError("unreachable"),
    }
}

/// returns 'x' truncated to the nearest int towards zero
inline fn impl(T: type, x: T) T {
    const Uint = @Int(.unsigned, @bitSizeOf(T));
    const u: Uint = @bitCast(x);

    const mbits = math.floatMantissaBits(T);
    const fbits = math.floatFractionalBits(T);
    const ebits = math.floatExponentBits(T);
    const explicit = mbits - fbits;

    const emask = (1 << ebits) - 1;
    const bias = emask >> 1;

    const expn: i32 = @intCast((u >> mbits) & emask);
    // if the integer bit is explicit (ie T == f80), we need to shift past it
    const e0: i32 = ebits + 1 + explicit;
    const e: i32 = expn - bias + e0;

    // if expn - bias >= fbits, x is an integer.
    if (e >= fbits + e0) return x;

    // @intCast(shift) is safe because:
    // * At this point, e < fbits + e0 and fbits + e0 == @bitSizeOf(T)
    // * shift <= 0 would mean e <= 0 and e >= e0, but e0 > 0
    const shift = if (e < e0) 1 else e;
    const mask = ~@as(Uint, 0) >> @intCast(shift);

    // At this point, the 1 bits of mask correspond to the fractional bits of x.
    // x is an integer iff they are all zero.
    if (u & mask == 0) return x;

    if (compiler_rt.want_float_exceptions) {
        // large enough to raise inexact but small enough to not raise overflow
        const large: T = switch (T) {
            f16 => 0x1p14,
            f32 => 0x1p126,
            f64 => 0x1p1022,
            f80 => 0x1p16382,
            f128 => 0x1p16382,
            else => @compileError("not a floating point type"),
        };
        std.mem.doNotOptimizeAway(x + large);
    }

    // zero out the fractional bits of x to produce the resulting integer
    return @bitCast(u & ~mask);
}

fn testImpl(T: type) !void {
    const fbits = math.floatFractionalBits(T);
    const U = @Int(.unsigned, @bitSizeOf(T));

    var u: U = 0;
    while (u < math.maxInt(U) / 3) {
        defer u = u + u / 3 + 1;
        const x: T = @floatFromInt(u);

        for ([_]T{ 0.0, 0.3, 0.5, 0.7 }) |frac| {
            const y = x + frac;

            const expected = if (u < (1 << fbits)) x else y;

            try expect(impl(T, y) == expected);
            try expect(impl(T, -y) == -expected);

            if (expected == 0.0) {
                try expect(math.signbit(impl(T, y)) == math.signbit(expected));
                try expect(math.signbit(impl(T, -y)) == math.signbit(-expected));
            }
        }
    }
}

test "trunc16" {
    try testImpl(f16);
}

test "trunc32" {
    try testImpl(f32);
}

test "trunc64" {
    try testImpl(f64);
}

test "trunc80" {
    try testImpl(f80);
}

test "trunc128" {
    try testImpl(f128);
}

fn testImplSpecial(T: type) !void {
    try expect(math.isPositiveZero(impl(T, 0.0)));
    try expect(math.isNegativeZero(impl(T, -0.0)));
    try expect(math.isPositiveInf(impl(T, math.inf(T))));
    try expect(math.isNegativeInf(impl(T, -math.inf(T))));
    try expect(math.isNan(impl(T, math.nan(T))));
}

test "trunc16.special" {
    try testImplSpecial(f16);
}

test "trunc32.special" {
    try testImplSpecial(f32);
}

test "trunc64.special" {
    try testImplSpecial(f64);
}

test "trunc80.special" {
    try testImplSpecial(f80);
}

test "trunc128.special" {
    try testImplSpecial(f128);
}
