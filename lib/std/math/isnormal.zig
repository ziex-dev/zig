const std = @import("../std.zig");
const math = std.math;
const expect = std.testing.expect;

/// Returns whether x is neither zero, subnormal, infinity, or NaN.
pub fn isNormal(x: anytype) bool {
    const T = @TypeOf(x);
    const TBits, const F = switch (@typeInfo(T)) {
        .float => |float| .{ std.meta.Int(.unsigned, float.bits), T },
        .comptime_float => .{ std.meta.Int(.unsigned, 128), f128 },
        else => unreachable,
    };

    const increment_exp = 1 << math.floatMantissaBits(T);
    const remove_sign = ~@as(TBits, 0) >> 1;

    // We add 1 to the exponent, and if it overflows to 0 or becomes 1,
    // then it was all zeroes (subnormal) or all ones (special, inf/nan).
    // The sign bit is removed because all ones would overflow into it.
    // For f80, even though it has an explicit integer part stored,
    // the exponent effectively takes priority if mismatching.
    const value = @as(TBits, @bitCast(@as(F, x))) +% increment_exp;
    return value & remove_sign >= (increment_exp << 1);
}

test isNormal {
    // TODO add `c_longdouble' when math.inf(T) supports it
    inline for ([_]type{ f16, f32, f64, f80, f128, comptime_float }) |T| {
        const TBits = switch (@typeInfo(T)) {
            .float => |float| std.meta.Int(.unsigned, float.bits),
            .comptime_float => std.meta.Int(.unsigned, 128),
            else => unreachable,
        };

        // normals
        try expect(isNormal(@as(T, 1.0)));
        try expect(isNormal(math.floatMin(T)));
        try expect(isNormal(math.floatMax(T)));

        // subnormals
        try expect(!isNormal(@as(T, -0.0)));
        try expect(!isNormal(@as(T, 0.0)));
        try expect(!isNormal(@as(T, math.floatTrueMin(T))));

        if (T == comptime_float) return;

        // largest subnormal
        try expect(!isNormal(@as(T, @bitCast(~(~@as(TBits, 0) << math.floatFractionalBits(T))))));

        // overflow edge-case (described in implementation, also see #10133)
        try expect(!isNormal(@as(T, @bitCast(~@as(TBits, 0)))));

        // non-finite numbers
        try expect(!isNormal(-math.inf(T)));
        try expect(!isNormal(math.inf(T)));
        try expect(!isNormal(math.nan(T)));
    }
}
