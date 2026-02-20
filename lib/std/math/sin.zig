// Ported from ARM-software, which is licensed under the MIT license:
// https://github.com/ARM-software/optimized-routines/blob/master/LICENSE
//
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/sinf.c
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/sin.c

const std = @import("std");
const math = std.math;
const testing = std.testing;

/// Returns the sine of x.
///
/// Special Cases:
///  - sin(+-inf) = nan
///  - sin(nan)  = nan
pub fn sin(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .float => return @sin(x),
        .vector => |info| switch (info.child) {
            f32 => return sinBinary32Vec(info.len, x),
            f64 => return sinBinary64Vec(info.len, x),
            else => @sin(x),
        },
        else => comptime unreachable,
    }
}

fn sinBinary32Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f32)) @TypeOf(x) {
    const c0: @Vector(vec_len, f32) = @splat(-0x1.555548p-3);
    const c1: @Vector(vec_len, f32) = @splat(0x1.110df4p-7);
    const c2: @Vector(vec_len, f32) = @splat(-0x1.9f42eap-13);
    const c3: @Vector(vec_len, f32) = @splat(0x1.5b2e76p-19);
    const neg_pi_high: @Vector(vec_len, f32) = @splat(-0x1.921fb6p+1);
    const neg_pi_mid: @Vector(vec_len, f32) = @splat(0x1.777a5cp-24);
    const neg_pi_low: @Vector(vec_len, f32) = @splat(0x1.ee59dap-49);
    const inv_pi: @Vector(vec_len, f32) = @splat(0x1.45f306p-2);
    const range_val: @Vector(vec_len, f32) = @splat(0x1.0p20);
    const shift: @Vector(vec_len, f32) = @splat(0x1.8p+23);
    const one: @Vector(vec_len, u32) = @splat(1);
    const shift_offest: @Vector(vec_len, u5) = @splat(31);

    const q = @mulAdd(@Vector(vec_len, f32), x, inv_pi, shift);
    const odd = (@as(@Vector(vec_len, u32), @bitCast(q)) & one) << shift_offest;
    const n = q - shift;
    var r = @mulAdd(@Vector(vec_len, f32), neg_pi_high, n, x);
    r = @mulAdd(@Vector(vec_len, f32), neg_pi_mid, n, r);
    r = @mulAdd(@Vector(vec_len, f32), neg_pi_low, n, r);
    const r2 = r * r;
    const r3 = r2 * r;
    var y = @mulAdd(@Vector(vec_len, f32), c3, r2, c2);
    y = @mulAdd(@Vector(vec_len, f32), y, r2, c1);
    y = @mulAdd(@Vector(vec_len, f32), y, r2, c0);
    y = @mulAdd(@Vector(vec_len, f32), y, r3, r);
    y = @bitCast(@as(@Vector(vec_len, u32), @bitCast(y)) ^ odd);
    const special = @abs(x) >= range_val;
    if (@reduce(.Or, special)) {
        @branchHint(.unlikely);
        inline for (0..vec_len) |i| {
            if (special[i]) y[i] = @sin(x[i]);
        }
    }
    return y;
}

fn sinBinary64Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f64)) @TypeOf(x) {
    const c0: @Vector(vec_len, f64) = @splat(-0x1.555555555547bp-3);
    const c1: @Vector(vec_len, f64) = @splat(0x1.1111111108a4dp-7);
    const c2: @Vector(vec_len, f64) = @splat(-0x1.a01a019936f27p-13);
    const c3: @Vector(vec_len, f64) = @splat(0x1.71de37a97d93ep-19);
    const c4: @Vector(vec_len, f64) = @splat(-0x1.ae633919987c6p-26);
    const c5: @Vector(vec_len, f64) = @splat(0x1.60e277ae07cecp-33);
    const c6: @Vector(vec_len, f64) = @splat(-0x1.9e9540300a1p-41);
    const inv_pi: @Vector(vec_len, f64) = @splat(0x1.45f306dc9c883p-2);
    const neg_pi_high: @Vector(vec_len, f64) = @splat(-0x1.921fb54442d18p+1);
    const neg_pi_mid: @Vector(vec_len, f64) = @splat(-0x1.1a62633145c06p-53);
    const neg_pi_low: @Vector(vec_len, f64) = @splat(-0x1.c1cd129024e09p-106);
    const range_val: @Vector(vec_len, f64) = @splat(0x1.0p23);
    const shift: @Vector(vec_len, f64) = @splat(0x1.8p52);
    const one: @Vector(vec_len, u64) = @splat(1);
    const shift_offest: @Vector(vec_len, u6) = @splat(63);

    const q = @mulAdd(@Vector(vec_len, f64), x, inv_pi, shift);
    const odd = (@as(@Vector(vec_len, u64), @bitCast(q)) & one) << shift_offest;
    const n = q - shift;
    var r = @mulAdd(@Vector(vec_len, f64), neg_pi_high, n, x);
    r = @mulAdd(@Vector(vec_len, f64), neg_pi_mid, n, r);
    r = @mulAdd(@Vector(vec_len, f64), neg_pi_low, n, r);
    const r2 = r * r;
    const r3 = r2 * r;
    const r4 = r2 * r2;
    const p0_1 = @mulAdd(@Vector(vec_len, f64), r2, c1, c0);
    const p2_3 = @mulAdd(@Vector(vec_len, f64), r2, c3, c2);
    const p4_5 = @mulAdd(@Vector(vec_len, f64), r2, c5, c4);
    const p4_6 = @mulAdd(@Vector(vec_len, f64), r4, c6, p4_5);
    const p2_6 = @mulAdd(@Vector(vec_len, f64), r4, p4_6, p2_3);
    const p0_6 = @mulAdd(@Vector(vec_len, f64), r4, p2_6, p0_1);
    var y = @mulAdd(@Vector(vec_len, f64), r3, p0_6, r);
    y = @bitCast(@as(@Vector(vec_len, u64), @bitCast(y)) ^ odd);
    const special = @abs(x) >= range_val;
    if (@reduce(.Or, special)) {
        @branchHint(.unlikely);
        inline for (0..vec_len) |i| {
            if (special[i]) y[i] = @sin(x[i]);
        }
    }
    return y;
}

test "sinBinary32Vec.special" {
    const input: @Vector(5, f32) = .{ 0x0p+0, -0x0p+0, math.inf(f32), -math.inf(f32), math.nan(f32) };
    const output = sinBinary32Vec(5, input);
    try testing.expectEqual(0x0p+0, output[0]);
    try testing.expectEqual(-0x0p+0, output[1]);
    try testing.expect(math.isNan(output[2]));
    try testing.expect(math.isNan(output[3]));
    try testing.expect(math.isNan(output[4]));
}

test "sinBinary32Vec" {
    const input: @Vector(10, f32) = .{
        -0x1.404254p18,
        -0x1.180012p17,
        -0x1.c7d504p18,
        -0x1.6ea0d6p19,
        0x1.035556p15,
        0x1.2a7d0ap20,
        -0x1.f23244p17,
        0x1.b7ccd8p12,
        -0x1.e4315ep19,
        -0x1.4970e8p18,
    };
    const output = sinBinary32Vec(10, input);
    try testing.expectApproxEqAbs(-0x1.58b272p-1, output[0], math.floatEpsAt(f32, -0x1.58b272p-1) * 2.0);
    try testing.expectApproxEqAbs(-0x1.401678p-3, output[1], math.floatEpsAt(f32, -0x1.401678p-3) * 2.0);
    try testing.expectApproxEqAbs(-0x1.f33116p-2, output[2], math.floatEpsAt(f32, -0x1.f33116p-2) * 2.0);
    try testing.expectApproxEqAbs(-0x1.fdbee4p-1, output[3], math.floatEpsAt(f32, -0x1.fdbee4p-1) * 2.0);
    try testing.expectApproxEqAbs(0x1.2117d6p-1, output[4], math.floatEpsAt(f32, 0x1.2117d6p-1) * 2.0);
    try testing.expectApproxEqAbs(0x1.ecad5p-1, output[5], math.floatEpsAt(f32, 0x1.ecad5p-1) * 2.0);
    try testing.expectApproxEqAbs(0x1.dd0132p-1, output[6], math.floatEpsAt(f32, 0x1.dd0132p-1) * 2.0);
    try testing.expectApproxEqAbs(-0x1.6d5582p-2, output[7], math.floatEpsAt(f32, -0x1.6d5582p-2) * 2.0);
    try testing.expectApproxEqAbs(-0x1.c281acp-1, output[8], math.floatEpsAt(f32, -0x1.c281acp-1) * 2.0);
    try testing.expectApproxEqAbs(0x1.0b77f2p-2, output[9], math.floatEpsAt(f32, 0x1.0b77f2p-2) * 2.0);
}

test "sinBinary64Vec.special" {
    const input: @Vector(5, f64) = .{ 0x0p+0, -0x0p+0, math.inf(f64), -math.inf(f64), math.nan(f64) };
    const output = sinBinary64Vec(5, input);
    try testing.expectEqual(0x0p+0, output[0]);
    try testing.expectEqual(-0x0p+0, output[1]);
    try testing.expect(math.isNan(output[2]));
    try testing.expect(math.isNan(output[3]));
    try testing.expect(math.isNan(output[4]));
}

test "sinBinary64Vec" {
    const input: @Vector(10, f64) = .{
        0x1.1ce653bf220ep18,
        0x1.f97d3b2af520cp21,
        -0x1.124b7db192a2p19,
        -0x1.5a595c82c75p15,
        -0x1.db5784fc363fep21,
        -0x1.d7cf5e4b35fbp19,
        0x1.8ddbefcdd5ffp22,
        0x1.37b4fa0c663f8p20,
        -0x1.87b16bcc8c89dp22,
        -0x1.1eb5518e8c82ep21,
    };
    const output = sinBinary64Vec(10, input);
    try testing.expectApproxEqAbs(0x1.9838f02c844ffp-2, output[0], math.floatEpsAt(f64, 0x1.9838f02c844ffp-2) * 3.0);
    try testing.expectApproxEqAbs(0x1.b288008169a2dp-2, output[1], math.floatEpsAt(f64, 0x1.b288008169a2dp-2) * 3.0);
    try testing.expectApproxEqAbs(-0x1.fcfe0cc2c48e6p-1, output[2], math.floatEpsAt(f64, -0x1.fcfe0cc2c48e6p-1) * 3.0);
    try testing.expectApproxEqAbs(0x1.fda50f6325ccep-1, output[3], math.floatEpsAt(f64, 0x1.fda50f6325ccep-1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.4b388b2793a24p-2, output[4], math.floatEpsAt(f64, -0x1.4b388b2793a24p-2) * 3.0);
    try testing.expectApproxEqAbs(-0x1.b1dbc39fe221ep-1, output[5], math.floatEpsAt(f64, -0x1.b1dbc39fe221ep-1) * 3.0);
    try testing.expectApproxEqAbs(0x1.ddd6ef1eb977ap-1, output[6], math.floatEpsAt(f64, 0x1.ddd6ef1eb977ap-1) * 3.0);
    try testing.expectApproxEqAbs(0x1.bc6b19ee6177cp-1, output[7], math.floatEpsAt(f64, 0x1.bc6b19ee6177cp-1) * 3.0);
    try testing.expectApproxEqAbs(0x1.cf76b91f8e942p-1, output[8], math.floatEpsAt(f64, 0x1.cf76b91f8e942p-1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.4d51707672ef3p-3, output[9], math.floatEpsAt(f64, -0x1.4d51707672ef3p-3) * 3.0);
}
