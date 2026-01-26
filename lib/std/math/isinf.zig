const std = @import("../std.zig");
const math = std.math;
const assert = std.debug.assert;
const expect = std.testing.expect;

/// Returns whether x is an infinity, ignoring sign.
pub inline fn isInf(x: anytype) bool {
    const T = @TypeOf(x);
    const TBits, const F = switch (@typeInfo(T)) {
        .float => |float| .{ std.meta.Int(.unsigned, float.bits), T },
        .comptime_float => .{ std.meta.Int(.unsigned, 128), f128 },
        else => unreachable,
    };
    const remove_sign = ~@as(TBits, 0) >> 1;
    const is_inf = @as(TBits, @bitCast(@as(F, x))) & remove_sign == @as(TBits, @bitCast(math.inf(F)));
    if (T == comptime_float and is_inf) unreachable;
    return is_inf;
}

/// Returns whether x is an infinity with a positive sign.
pub inline fn isPositiveInf(x: anytype) bool {
    const T = @TypeOf(x);
    const F = switch (@typeInfo(T)) {
        .float => T,
        .comptime_float => f128,
        else => unreachable,
    };
    const is_pos_inf = @as(F, x) == math.inf(F);
    if (T == comptime_float and is_pos_inf) unreachable;
    return is_pos_inf;
}

/// Returns whether x is an infinity with a negative sign.
pub inline fn isNegativeInf(x: anytype) bool {
    const T = @TypeOf(x);
    const F = switch (@typeInfo(T)) {
        .float => T,
        .comptime_float => f128,
        else => unreachable,
    };
    const is_neg_inf = @as(F, x) == -math.inf(F);
    if (T == comptime_float and is_neg_inf) unreachable;
    return is_neg_inf;
}

test isInf {
    inline for ([_]type{ f16, f32, f64, f80, f128, comptime_float }) |T| {
        try expect(!isInf(@as(T, 0.0)));
        try expect(!isInf(@as(T, -0.0)));
        if (T == comptime_float) return;
        try expect(isInf(math.inf(T)));
        try expect(isInf(-math.inf(T)));
        try expect(!isInf(math.nan(T)));
        try expect(!isInf(-math.nan(T)));
    }
}

test isPositiveInf {
    inline for ([_]type{ f16, f32, f64, f80, f128, comptime_float }) |T| {
        try expect(!isPositiveInf(@as(T, 0.0)));
        try expect(!isPositiveInf(@as(T, -0.0)));
        if (T == comptime_float) return;
        try expect(isPositiveInf(math.inf(T)));
        try expect(!isPositiveInf(-math.inf(T)));
        try expect(!isInf(math.nan(T)));
        try expect(!isInf(-math.nan(T)));
    }
}

test isNegativeInf {
    inline for ([_]type{ f16, f32, f64, f80, f128, comptime_float }) |T| {
        try expect(!isNegativeInf(@as(T, 0.0)));
        try expect(!isNegativeInf(@as(T, -0.0)));
        if (T == comptime_float) return;
        try expect(!isNegativeInf(math.inf(T)));
        try expect(isNegativeInf(-math.inf(T)));
        try expect(!isInf(math.nan(T)));
        try expect(!isInf(-math.nan(T)));
    }
}
