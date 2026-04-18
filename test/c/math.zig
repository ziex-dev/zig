const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const math = std.math;

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectApproxEqAbs = testing.expectApproxEqAbs;
const expectApproxEqRel = testing.expectApproxEqRel;

fn testModf(comptime T: type) !void {
    const f = switch (T) {
        f32 => c.modff,
        f64 => c.modf,
        c_longdouble => c.modfl,
        else => unreachable,
    };

    var int: T = undefined;
    const iptr = &int;
    const eps_val: comptime_float = @max(1e-6, math.floatEps(T));

    const normal_frac = f(@as(T, 1234.567), iptr);
    // Account for precision error
    const expected = 1234.567 - @as(T, 1234);
    try expectApproxEqAbs(expected, normal_frac, eps_val);
    try expectApproxEqRel(@as(T, 1234.0), iptr.*, eps_val);

    // When `x` is a NaN, NaN is returned and `*iptr` is set to NaN
    const nan_frac = f(math.nan(T), iptr);
    try expect(math.isNan(nan_frac));
    try expect(math.isNan(iptr.*));

    // When `x` is positive infinity, +0 is returned and `*iptr` is set to
    // positive infinity
    const pos_zero_frac = f(math.inf(T), iptr);
    try expect(math.isPositiveZero(pos_zero_frac));
    try expect(math.isPositiveInf(iptr.*));

    // When `x` is negative infinity, -0 is returned and `*iptr` is set to
    // negative infinity
    const neg_zero_frac = f(-math.inf(T), iptr);
    try expect(math.isNegativeZero(neg_zero_frac));
    try expect(math.isNegativeInf(iptr.*));

    // Return -0 when `x` is a negative integer
    const nz_frac = f(@as(T, -1000.0), iptr);
    try expect(math.isNegativeZero(nz_frac));
    try expectEqual(@as(T, -1000.0), iptr.*);

    // Return +0 when `x` is a positive integer
    const pz_frac = f(@as(T, 1000.0), iptr);
    try expect(math.isPositiveZero(pz_frac));
    try expectEqual(@as(T, 1000.0), iptr.*);
}

test "modf" {
    try testModf(f32);
    try testModf(f64);

    if (builtin.target.cpu.arch.isPowerPC()) return error.SkipZigTest; // TODO

    try testModf(c_longdouble);
}

fn testRintSpecial(comptime T: type) !void {
    const f = switch (T) {
        f32 => c.rintf,
        f64 => c.rint,
        c_longdouble => c.rintl,
        else => @compileError("rint not implemented for" ++ @typeName(T)),
    };

    // For the special cases, x itself should be returned
    try expectEqual(0.0, f(0.0));
    try expectEqual(-0.0, f(-0.0));
    try expectEqual(math.inf(T), f(math.inf(T)));
    try expectEqual(-math.inf(T), f(-math.inf(T)));
    try expect(math.isNan(f(math.nan(T))));
}

fn testRintNormal(comptime T: type) !void {
    const f = switch (T) {
        f32 => c.rintf,
        f64 => c.rint,
        c_longdouble => c.rintl,
        else => @compileError("rint not implemented for" ++ @typeName(T)),
    };

    // Positive numbers round correctly
    try expectEqual(@as(T, 42.0), f(42.2));
    try expectEqual(@as(T, 42.0), f(41.8));
    try expectEqual(@as(T, 16_777_216.0), f(16_777_215.6));

    // Negative numbers round correctly
    try expectEqual(@as(T, -6.0), f(-5.9));
    try expectEqual(@as(T, -6.0), f(-6.1));
    try expectEqual(@as(T, -16_777_215.0), f(-16_777_215.4));

    // No rounding needed test
    try expectEqual(@as(T, 5.0), f(5.0));
    try expectEqual(@as(T, -10.0), f(-10.0));
    try expectEqual(@as(T, 0.0), f(0.0));

    // Very large numbers return unchanged
    const large: T = 9007199254740992.0; // 2^53
    try expectEqual(large, f(large));
    try expectEqual(-large, f(-large));

    // Small positive numbers round to zero
    const pos_result = f(0.3);
    try expect(math.isPositiveZero(pos_result));

    // Small negative numbers round to negative zero
    try expectEqual(@as(T, -0.0), f(-0.3));

    // Exact half rounds to nearest even (banker's rounding)
    try expectEqual(@as(T, 2.0), f(2.5));
    try expectEqual(@as(T, 4.0), f(3.5));
}

test "rintf.special" {
    try testRintSpecial(f32);
}

test "rintf.normal" {
    try testRintNormal(f32);
}

test "rint.special" {
    try testRintSpecial(f64);
}

test "rint.normal" {
    try testRintNormal(f64);
}

test "rintl.special" {
    try testRintSpecial(c_longdouble);
}

test "rintl.normal" {
    try testRintNormal(c_longdouble);
}
