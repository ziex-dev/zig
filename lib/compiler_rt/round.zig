//! Ported from musl, which is licensed under the MIT license:
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/roundf.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/round.c

const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const mem = std.mem;
const expect = std.testing.expect;
const arch = builtin.cpu.arch;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__roundh, "__roundh");
    symbol(&roundf, "roundf");
    symbol(&round, "round");
    symbol(&__roundx, "__roundx");
    if (compiler_rt.want_ppc_abi) {
        symbol(&roundq, "roundf128");
    }
    symbol(&roundq, "roundq");
    symbol(&roundl, "roundl");
}

pub fn __roundh(x: f16) callconv(.c) f16 {
    return impl(f16, x);
}

pub fn roundf(x: f32) callconv(.c) f32 {
    return impl(f32, x);
}

pub fn round(x: f64) callconv(.c) f64 {
    return impl(f64, x);
}

pub fn __roundx(x: f80) callconv(.c) f80 {
    return impl(f80, x);
}

pub fn roundq(x: f128) callconv(.c) f128 {
    return impl(f128, x);
}

pub fn roundl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return round(x),
        80 => return __roundx(x),
        128 => return roundq(x),
        else => @compileError("unreachable"),
    }
}

/// returns 'x' rounded to the nearest integer, ties away from zero
inline fn impl(T: type, x: T) T {
    const size = @bitSizeOf(T);
    const U = @Int(.unsigned, size);

    const fbits = math.floatFractionalBits(T);
    const mbits = math.floatMantissaBits(T);
    const ebits = math.floatExponentBits(T);
    const emask = (1 << ebits) - 1;
    const smask: U = 1 << (size - 1);
    const bias = emask >> 1;

    const toint = 1.0 / math.floatEps(T);

    const bits: U = @bitCast(x);
    const expn = (bits >> mbits) & emask;
    const is_negative = bits & smask != 0;

    // filter out NaNs and +-inf, and |x| >= 2^fbits which are already integers
    if (expn >= bias + fbits) return x;

    // if |x| < 0.5, return +-zero
    if (expn < bias - 1) {
        if (compiler_rt.want_float_exceptions)
            std.mem.doNotOptimizeAway(x + toint);
        return @bitCast(bits & smask);
    }

    const a = if (is_negative) -x else x;

    const rounded = a + toint - toint;
    const delta = rounded - a;
    // Apply correction to round ties away from zero
    const result =
        if (delta > 0.5)
            rounded - 1
        else if (delta <= -0.5)
            rounded + 1
        else
            rounded;

    return if (is_negative) -result else result;
}

fn testRound(T: type) !void {
    const U = @Int(.unsigned, @bitSizeOf(T));

    var u: U = 0;
    while (u < math.maxInt(U) / 3) {
        defer u = u + u / 3 + 1;
        const x: T = @floatFromInt(u);

        for ([_]T{ 0.0, 0.1, 0.5, 0.7 }) |frac| {
            const y = x + frac;
            const expected = if (x != y and frac >= 0.5) x + 1 else x;

            try expect(impl(T, y) == expected);
            try expect(impl(T, -y) == -expected);

            if (expected == 0.0) {
                try expect(math.signbit(impl(T, y)) == math.signbit(expected));
                try expect(math.signbit(impl(T, -y)) == math.signbit(-expected));
            }
        }
    }
}

test "round16" {
    try testRound(f16);
}

test "round32" {
    try testRound(f32);
}

test "round64" {
    try testRound(f64);
}

test "round80" {
    try testRound(f80);
}

test "round128" {
    try testRound(f128);
}

fn testRoundSpecial(T: type) !void {
    try expect(math.isPositiveZero(impl(T, 0.0)));
    try expect(math.isNegativeZero(impl(T, -0.0)));
    try expect(math.isPositiveInf(impl(T, math.inf(T))));
    try expect(math.isNegativeInf(impl(T, -math.inf(T))));
    try expect(math.isNan(impl(T, math.nan(T))));
}

test "round16.special" {
    try testRoundSpecial(f16);
}

test "round32.special" {
    try testRoundSpecial(f32);
}

test "round64.special" {
    try testRoundSpecial(f64);
}

test "round80.special" {
    try testRoundSpecial(f80);
}

test "round128.special" {
    try testRoundSpecial(f128);
}
