// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/src/math/acoshf.c
// https://git.musl-libc.org/cgit/musl/tree/src/math/acosh.c

const std = @import("../std.zig");
const math = std.math;
const expect = std.testing.expect;

/// Returns the hyperbolic arc-cosine of x.
///
/// Special cases:
///  - acosh(x)   = nan if x < 1
///  - acosh(nan) = nan
pub fn acosh(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    return switch (T) {
        f32 => acosh32(x),
        f64 => acosh64(x),
        else => @compileError("acosh not implemented for " ++ @typeName(T)),
    };
}

// acosh(x) = log(x + sqrt(x * x - 1))
fn acosh32(x: f32) f32 {
    const u = @as(u32, @bitCast(x));
    const i = u & 0x7FFFFFFF;

    // |x| < 2, invalid if x < 1 or nan
    if (i < 0x3F800000 + (1 << 23)) {
        return math.log1p(x - 1 + @sqrt((x - 1) * (x - 1) + 2 * (x - 1)));
    }
    // |x| < 0x1p12
    else if (i < 0x3F800000 + (12 << 23)) {
        return @log(2 * x - 1 / (x + @sqrt(x * x - 1)));
    }
    // |x| >= 0x1p12
    else {
        return @log(x) + 0.693147180559945309417232121458176568;
    }
}

pub fn acosh64(x: f64) f64 {
    const ln2: f64 = 6.93147180559945286227e-01; // 0x3FE62E42, 0xFEFA39EF

    const bits: u64 = @bitCast(x);
    const hx: i32 = @bitCast(@as(u32, @truncate(bits >> 32))); // high 32 bits as signed
    const lx: u32 = @truncate(bits); // low 32 bits

    if (hx < 0x3FF00000) { // x < 1
        return (x - x) / (x - x); // return NaN
    } else if (hx >= 0x41B00000) { // x > 2**28
        if (hx >= 0x7FF00000) { // x is inf or NaN
            return x + x;
        } else {
            return @log(x) + ln2; // acosh64(huge) = log(2x)
        }
    } else if (hx == 0x3FF00000 and lx == 0) { // x == 1.0
        return 0.0; // acosh64(1) = 0
    } else if (hx > 0x40000000) { // 2**28 > x > 2
        const t = x * x;
        return @log(2.0 * x - 1.0 / (x + @sqrt(t - 1.0)));
    } else { // 1 < x < 2
        const t = x - 1.0;
        return math.log1p(t + @sqrt(2.0 * t + t * t));
    }
}

test acosh {
    try expect(acosh(@as(f32, 1.5)) == acosh32(1.5));
    try expect(acosh(@as(f64, 1.5)) == acosh64(1.5));
}

test acosh32 {
    const epsilon = 0.000001;

    try expect(math.approxEqAbs(f32, acosh32(1.5), 0.962424, epsilon));
    try expect(math.approxEqAbs(f32, acosh32(37.45), 4.315976, epsilon));
    try expect(math.approxEqAbs(f32, acosh32(89.123), 5.183133, epsilon));
    try expect(math.approxEqAbs(f32, acosh32(123123.234375), 12.414088, epsilon));
}

test acosh64 {
    const epsilon = 0.000001;

    try expect(math.approxEqAbs(f64, acosh64(1.5), 0.962424, epsilon));
    try expect(math.approxEqAbs(f64, acosh64(37.45), 4.315976, epsilon));
    try expect(math.approxEqAbs(f64, acosh64(89.123), 5.183133, epsilon));
    try expect(math.approxEqAbs(f64, acosh64(123123.234375), 12.414088, epsilon));
}

test "acosh32.special" {
    try expect(math.isNan(acosh32(math.nan(f32))));
    try expect(math.isNan(acosh32(0.5)));
}

test "acosh64.special" {
    try expect(math.isNan(acosh64(math.nan(f64))));
    try expect(math.isNan(acosh64(0.5)));
}

test "acosh returns NaN for x < 1" {
    try std.testing.expect(math.isNan(math.acosh(@as(f64, -1.9e4))));
    try std.testing.expect(math.isNan(math.acosh(@as(f64, -2e4))));
    try std.testing.expect(math.isNan(math.acosh(@as(f32, -1.9e4))));
    try std.testing.expect(math.isNan(math.acosh(@as(f32, -2e4))));
}
