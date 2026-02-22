// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/src/math/atan2f.c
// https://git.musl-libc.org/cgit/musl/tree/src/math/atan2.c

const std = @import("../std.zig");
const builtin = @import("builtin");
const math = std.math;
const expect = std.testing.expect;

/// Returns the arc-tangent of y/x.
///
///      Special Cases:
/// |   y   |   x   | radians |
/// |-------|-------|---------|
/// |  fin  |  nan  |   nan   |
/// |  nan  |  fin  |   nan   |
/// |  +0   | >=+0  |   +0    |
/// |  -0   | >=+0  |   -0    |
/// |  +0   | <=-0  |   pi    |
/// |  -0   | <=-0  |  -pi    |
/// |  pos  |   0   |  +pi/2  |
/// |  neg  |   0   |  -pi/2  |
/// | +inf  | +inf  |  +pi/4  |
/// | -inf  | +inf  |  -pi/4  |
/// | +inf  | -inf  |  3pi/4  |
/// | -inf  | -inf  | -3pi/4  |
/// |  fin  | +inf  |    0    |
/// |  pos  | -inf  |  +pi    |
/// |  neg  | -inf  |  -pi    |
/// | +inf  |  fin  |  +pi/2  |
/// | -inf  |  fin  |  -pi/2  |
pub fn atan2(y: anytype, x: anytype) @TypeOf(x, y) {
    const T = @TypeOf(x, y);
    return switch (T) {
        f16 => atan2_16(y, x),
        f32 => atan2_32(y, x),
        f64 => atan2_64(y, x),
        f80 => atan2_80(y, x),
        f128 => atan2_128(y, x),
        else => @compileError("atan2 not implemented for " ++ @typeName(T)),
    };
}

fn atan2_generic(comptime T: type, y: T, x: T) T {
    const pi: T = @floatCast(math.pi);
    const pi_over_2: T = pi / 2.0;
    const pi_over_4: T = pi / 4.0;

    if (math.isNan(x) or math.isNan(y)) {
        return x + y;
    }

    if (y == 0.0) {
        if (math.signbit(x)) {
            return math.copysign(pi, y);
        }
        return y;
    }

    if (x == 0.0) {
        return math.copysign(pi_over_2, y);
    }

    if (math.isInf(x)) {
        if (math.isInf(y)) {
            if (math.signbit(x)) {
                return math.copysign(3.0 * pi_over_4, y);
            }
            return math.copysign(pi_over_4, y);
        }
        if (math.signbit(x)) {
            return math.copysign(pi, y);
        }
        return math.copysign(@as(T, 0.0), y);
    }

    if (math.isInf(y)) {
        return math.copysign(pi_over_2, y);
    }

    const z = math.atan(@abs(y / x));
    if (math.signbit(x)) {
        return math.copysign(pi - z, y);
    }
    return math.copysign(z, y);
}

fn atan2_16(y: f16, x: f16) f16 {
    return atan2_generic(f16, y, x);
}

fn atan2_32(y: f32, x: f32) f32 {
    const pi: f32 = 3.1415927410e+00;
    const pi_lo: f32 = -8.7422776573e-08;

    if (math.isNan(x) or math.isNan(y)) {
        return x + y;
    }

    var ix = @as(u32, @bitCast(x));
    var iy = @as(u32, @bitCast(y));

    // x = 1.0
    if (ix == 0x3F800000) {
        return math.atan(y);
    }

    // 2 * sign(x) + sign(y)
    const m = ((iy >> 31) & 1) | ((ix >> 30) & 2);
    ix &= 0x7FFFFFFF;
    iy &= 0x7FFFFFFF;

    if (iy == 0) {
        switch (m) {
            0, 1 => return y, // atan(+-0, +...)
            2 => return pi, // atan(+0, -...)
            3 => return -pi, // atan(-0, -...)
            else => unreachable,
        }
    }

    if (ix == 0) {
        if (m & 1 != 0) {
            return -pi / 2;
        } else {
            return pi / 2;
        }
    }

    if (ix == 0x7F800000) {
        if (iy == 0x7F800000) {
            switch (m) {
                0 => return pi / 4, // atan(+inf, +inf)
                1 => return -pi / 4, // atan(-inf, +inf)
                2 => return 3 * pi / 4, // atan(+inf, -inf)
                3 => return -3 * pi / 4, // atan(-inf, -inf)
                else => unreachable,
            }
        } else {
            switch (m) {
                0 => return 0.0, // atan(+..., +inf)
                1 => return -0.0, // atan(-..., +inf)
                2 => return pi, // atan(+..., -inf)
                3 => return -pi, // atan(-...f, -inf)
                else => unreachable,
            }
        }
    }

    // |y / x| > 0x1p26
    if (ix + (26 << 23) < iy or iy == 0x7F800000) {
        if (m & 1 != 0) {
            return -pi / 2;
        } else {
            return pi / 2;
        }
    }

    // z = atan(|y / x|) with correct underflow
    const z = z: {
        if ((m & 2) != 0 and iy + (26 << 23) < ix) {
            break :z 0.0;
        } else {
            break :z math.atan(@abs(y / x));
        }
    };

    switch (m) {
        0 => return z, // atan(+, +)
        1 => return -z, // atan(-, +)
        2 => return pi - (z - pi_lo), // atan(+, -)
        3 => return (z - pi_lo) - pi, // atan(-, -)
        else => unreachable,
    }
}

fn atan2_64(y: f64, x: f64) f64 {
    const pi: f64 = 3.1415926535897931160E+00;
    const pi_lo: f64 = 1.2246467991473531772E-16;

    if (math.isNan(x) or math.isNan(y)) {
        return x + y;
    }

    const ux: u64 = @bitCast(x);
    var ix: u32 = @intCast(ux >> 32);
    const lx: u32 = @intCast(ux & 0xFFFFFFFF);

    const uy: u64 = @bitCast(y);
    var iy: u32 = @intCast(uy >> 32);
    const ly: u32 = @intCast(uy & 0xFFFFFFFF);

    // x = 1.0
    if ((ix -% 0x3FF00000) | lx == 0) {
        return math.atan(y);
    }

    // 2 * sign(x) + sign(y)
    const m = ((iy >> 31) & 1) | ((ix >> 30) & 2);
    ix &= 0x7FFFFFFF;
    iy &= 0x7FFFFFFF;

    if (iy | ly == 0) {
        switch (m) {
            0, 1 => return y, // atan(+-0, +...)
            2 => return pi, // atan(+0, -...)
            3 => return -pi, // atan(-0, -...)
            else => unreachable,
        }
    }

    if (ix | lx == 0) {
        if (m & 1 != 0) {
            return -pi / 2;
        } else {
            return pi / 2;
        }
    }

    if (ix == 0x7FF00000) {
        if (iy == 0x7FF00000) {
            switch (m) {
                0 => return pi / 4, // atan(+inf, +inf)
                1 => return -pi / 4, // atan(-inf, +inf)
                2 => return 3 * pi / 4, // atan(+inf, -inf)
                3 => return -3 * pi / 4, // atan(-inf, -inf)
                else => unreachable,
            }
        } else {
            switch (m) {
                0 => return 0.0, // atan(+..., +inf)
                1 => return -0.0, // atan(-..., +inf)
                2 => return pi, // atan(+..., -inf)
                3 => return -pi, // atan(-...f, -inf)
                else => unreachable,
            }
        }
    }

    // |y / x| > 0x1p64
    if (ix +% (64 << 20) < iy or iy == 0x7FF00000) {
        if (m & 1 != 0) {
            return -pi / 2;
        } else {
            return pi / 2;
        }
    }

    // z = atan(|y / x|) with correct underflow
    const z = z: {
        if ((m & 2) != 0 and iy +% (64 << 20) < ix) {
            break :z 0.0;
        } else {
            break :z math.atan(@abs(y / x));
        }
    };

    switch (m) {
        0 => return z, // atan(+, +)
        1 => return -z, // atan(-, +)
        2 => return pi - (z - pi_lo), // atan(+, -)
        3 => return (z - pi_lo) - pi, // atan(-, -)
        else => unreachable,
    }
}

fn atan2_80(y: f80, x: f80) f80 {
    return atan2_generic(f80, y, x);
}

fn atan2_128(y: f128, x: f128) f128 {
    return atan2_generic(f128, y, x);
}

test atan2 {
    const y16: f16 = 0.2;
    const x16: f16 = 0.21;
    const y32: f32 = 0.2;
    const x32: f32 = 0.21;
    const y64: f64 = 0.2;
    const x64: f64 = 0.21;
    const y80: f80 = 0.2;
    const x80: f80 = 0.21;
    const y128: f128 = 0.2;
    const x128: f128 = 0.21;
    try expect(atan2(y16, x16) == atan2_16(0.2, 0.21));
    try expect(atan2(y32, x32) == atan2_32(0.2, 0.21));
    try expect(atan2(y64, x64) == atan2_64(0.2, 0.21));
    try expect(atan2(y80, x80) == atan2_80(0.2, 0.21));
    try expect(atan2(y128, x128) == atan2_128(0.2, 0.21));
}

test atan2_generic {
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        const epsilon: T = switch (T) {
            f16 => 0.005,
            else => 0.002,
        };
        const cases = [_]struct { y: T, x: T, expected: T }{
            .{ .y = 0.0, .x = 0.0, .expected = 0.0 },
            .{ .y = 0.2, .x = 0.2, .expected = 0.7852 },
            .{ .y = -0.2, .x = 0.2, .expected = -0.7852 },
            .{ .y = 0.2, .x = -0.2, .expected = 2.355 },
            .{ .y = -0.2, .x = -0.2, .expected = -2.355 },
        };

        inline for (cases) |case| {
            try expect(math.approxEqAbs(T, atan2(case.y, case.x), case.expected, epsilon));
        }
    }
}

fn testAtan2Accuracy(comptime T: type, epsilon: T) !void {
    try expect(math.approxEqAbs(T, atan2(@as(T, 0.0), @as(T, 0.0)), @as(T, 0.0), epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, 0.2), @as(T, 0.2)), @floatCast(0.785398), epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, -0.2), @as(T, 0.2)), @floatCast(-0.785398), epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, 0.2), @as(T, -0.2)), @floatCast(2.356194), epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, -0.2), @as(T, -0.2)), @floatCast(-2.356194), epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, 0.34), @as(T, -0.4)), @floatCast(2.437099), epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, 0.34), @as(T, 1.243)), @floatCast(0.267001), epsilon));
}

fn testAtan2Special(comptime T: type, epsilon: T) !void {
    const pi: T = @floatCast(math.pi);

    try expect(math.isNan(atan2(@as(T, 1.0), math.nan(T))));
    try expect(math.isNan(atan2(math.nan(T), @as(T, 1.0))));
    try expect(atan2(@as(T, 0.0), @as(T, 5.0)) == 0.0);
    try expect(atan2(@as(T, -0.0), @as(T, 5.0)) == -0.0);
    try expect(math.approxEqAbs(T, atan2(@as(T, 0.0), @as(T, -5.0)), pi, epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, 1.0), @as(T, 0.0)), pi / 2.0, epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, 1.0), @as(T, -0.0)), pi / 2.0, epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, -1.0), @as(T, 0.0)), -pi / 2.0, epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, -1.0), @as(T, -0.0)), -pi / 2.0, epsilon));
    try expect(math.approxEqAbs(T, atan2(math.inf(T), math.inf(T)), pi / 4.0, epsilon));
    try expect(math.approxEqAbs(T, atan2(-math.inf(T), math.inf(T)), -pi / 4.0, epsilon));
    try expect(math.approxEqAbs(T, atan2(math.inf(T), -math.inf(T)), 3.0 * pi / 4.0, epsilon));
    try expect(math.approxEqAbs(T, atan2(-math.inf(T), -math.inf(T)), -3.0 * pi / 4.0, epsilon));
    try expect(atan2(@as(T, 1.0), math.inf(T)) == 0.0);
    try expect(math.approxEqAbs(T, atan2(@as(T, 1.0), -math.inf(T)), pi, epsilon));
    try expect(math.approxEqAbs(T, atan2(@as(T, -1.0), -math.inf(T)), -pi, epsilon));
    try expect(math.approxEqAbs(T, atan2(math.inf(T), @as(T, 1.0)), pi / 2.0, epsilon));
    try expect(math.approxEqAbs(T, atan2(-math.inf(T), @as(T, 1.0)), -pi / 2.0, epsilon));
}

fn testAtan2TinyOverHuge(comptime T: type, huge_x: T) !void {
    const y1: T = 0x1p+0;
    const y2: T = 0x1.8p+0;

    const r1 = atan2(y1, huge_x);
    const r2 = atan2(y2, huge_x);

    try expect(r1 != 0.0);
    try expect(r2 != 0.0);
}

test "atan2_float_types" {
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        const epsilon: T = switch (T) {
            f16 => 0.005,
            else => 0.000001,
        };

        try testAtan2Accuracy(T, epsilon);
        try testAtan2Special(T, epsilon);
    }
}

test "atan2_flushed_to_zero_regression" {
    if (builtin.cpu.arch.isArm() or
        builtin.cpu.arch.isMIPS32())
    {
        return error.SkipZigTest;
    }
    try testAtan2TinyOverHuge(f16, 0x1p+15);
    try testAtan2TinyOverHuge(f32, 0x1p+127);
    try testAtan2TinyOverHuge(f64, 0x1p+1023);
    //try testAtan2TinyOverHuge(f80, 0x1p+16383);
    try testAtan2TinyOverHuge(f128, 0x1p+16383);
}
