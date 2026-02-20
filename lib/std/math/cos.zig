// Ported from ARM-software, which is licensed under the MIT license:
// https://github.com/ARM-software/optimized-routines/blob/master/LICENSE
//
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/cosf.c
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/cos.c

const std = @import("std");
const math = std.math;
const testing = std.testing;

/// Returns the cosine of x.
///
/// Special Cases:
///  - cos(+-inf) = nan
///  - cos(nan)  = nan
pub fn cos(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .float => return @cos(x),
        .vector => |info| switch (info.child) {
            f32 => return cosBinary32Vec(info.len, x),
            f64 => return cosBinary64Vec(info.len, x),
            else => @cos(x),
        },
        else => comptime unreachable,
    }
}

fn cosBinary32Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f32)) @TypeOf(x) {
    const c0: @Vector(vec_len, f32) = @splat(-0x1.555548p-3);
    const c1: @Vector(vec_len, f32) = @splat(0x1.110df4p-7);
    const c2: @Vector(vec_len, f32) = @splat(-0x1.9f42eap-13);
    const c3: @Vector(vec_len, f32) = @splat(0x1.5b2e76p-19);
    const neg_pi_high: @Vector(vec_len, f32) = @splat(-0x1.921fb6p+1);
    const neg_pi_mid: @Vector(vec_len, f32) = @splat(0x1.777a5cp-24);
    const neg_pi_low: @Vector(vec_len, f32) = @splat(0x1.ee59dap-49);
    const inv_pi: @Vector(vec_len, f32) = @splat(0x1.45f306p-2);
    const range_val: @Vector(vec_len, f32) = @splat(0x1p20);
    const half: @Vector(vec_len, f32) = @splat(0.5);
    const shift: @Vector(vec_len, f32) = @splat(0x1.8p+23);
    const one: @Vector(vec_len, u32) = @splat(1);
    const shift_offest: @Vector(vec_len, u5) = @splat(31);

    const q = @mulAdd(@Vector(vec_len, f32), x, inv_pi, half) + shift;
    const odd = (@as(@Vector(vec_len, u32), @bitCast(q)) & one) << shift_offest;
    const n = q - shift - half;
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
            if (special[i]) y[i] = @cos(x[i]);
        }
    }
    return y;
}

fn cosBinary64Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f64)) @TypeOf(x) {
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
    const range_val: @Vector(vec_len, f64) = @splat(0x1p23);
    const half: @Vector(vec_len, f64) = @splat(0.5);
    const shift: @Vector(vec_len, f64) = @splat(0x1.8p52);
    const one: @Vector(vec_len, u64) = @splat(1);
    const shift_offest: @Vector(vec_len, u6) = @splat(63);

    const q = @mulAdd(@Vector(vec_len, f64), x, inv_pi, half) + shift;
    const odd = (@as(@Vector(vec_len, u64), @bitCast(q)) & one) << shift_offest;
    const n = q - shift - half;
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
            if (special[i]) y[i] = @cos(x[i]);
        }
    }
    return y;
}

test "cosBinary32Vec.special" {
    const input: @Vector(5, f32) = .{ 0x0p+0, -0x0p+0, math.inf(f32), -math.inf(f32), math.nan(f32) };
    const output = cosBinary32Vec(5, input);
    try testing.expectApproxEqAbs(0x1p+0, output[0], math.floatEpsAt(f32, 0x1p+0) * 2.0);
    try testing.expectApproxEqAbs(0x1p+0, output[1], math.floatEpsAt(f32, 0x1p+0) * 2.0);
    try testing.expect(math.isNan(output[2]));
    try testing.expect(math.isNan(output[3]));
    try testing.expect(math.isNan(output[4]));
}

test "cosBinary32Vec" {
    const input: @Vector(10, f32) = .{
        -0x1.117c82p20,
        0x1.97fd1ep19,
        0x1.162d62p17,
        -0x1.698eecp19,
        -0x1.41763p17,
        0x1.881d1p19,
        -0x1.d68f0ep18,
        0x1.c30dc2p14,
        0x1.466036p18,
        0x1.0e4098p19,
    };
    const output = cosBinary32Vec(10, input);
    try testing.expectApproxEqAbs(-0x1.84964cp-1, output[0], math.floatEpsAt(f32, -0x1.84964cp-1) * 2.0);
    try testing.expectApproxEqAbs(-0x1.23e07ep-1, output[1], math.floatEpsAt(f32, -0x1.23e07ep-1) * 2.0);
    try testing.expectApproxEqAbs(0x1.c6659cp-1, output[2], math.floatEpsAt(f32, 0x1.c6659cp-1) * 2.0);
    try testing.expectApproxEqAbs(-0x1.b69ebcp-2, output[3], math.floatEpsAt(f32, -0x1.b69ebcp-2) * 2.0);
    try testing.expectApproxEqAbs(0x1.e363d8p-1, output[4], math.floatEpsAt(f32, 0x1.e363d8p-1) * 2.0);
    try testing.expectApproxEqAbs(0x1.4a835ep-1, output[5], math.floatEpsAt(f32, 0x1.4a835ep-1) * 2.0);
    try testing.expectApproxEqAbs(0x1.0ba554p-1, output[6], math.floatEpsAt(f32, 0x1.0ba554p-1) * 2.0);
    try testing.expectApproxEqAbs(-0x1.95e72ep-1, output[7], math.floatEpsAt(f32, -0x1.95e72ep-1) * 2.0);
    try testing.expectApproxEqAbs(0x1.fee348p-1, output[8], math.floatEpsAt(f32, 0x1.fee348p-1) * 2.0);
    try testing.expectApproxEqAbs(-0x1.db45eap-1, output[9], math.floatEpsAt(f32, -0x1.db45eap-1) * 2.0);
}

test "cosBinary64Vec.special" {
    const input: @Vector(5, f64) = .{ 0x0p+0, -0x0p+0, math.inf(f64), -math.inf(f64), math.nan(f64) };
    const output = cosBinary64Vec(5, input);
    try testing.expectApproxEqAbs(0x1p+0, output[0], math.floatEpsAt(f64, 0x1p+0) * 3.0);
    try testing.expectApproxEqAbs(0x1p+0, output[1], math.floatEpsAt(f64, 0x1p+0) * 3.0);
    try testing.expect(math.isNan(output[2]));
    try testing.expect(math.isNan(output[3]));
    try testing.expect(math.isNan(output[4]));
}

test "cosBinary64Vec" {
    const input: @Vector(10, f64) = .{
        -0x1.484f6deab67e4p20,
        -0x1.15538163a5e67p23,
        0x1.32b6b1b65ea88p22,
        -0x1.7d6167092cb84p22,
        -0x1.733a200b25fep18,
        -0x1.77d9af5d307acp21,
        -0x1.0138511749dc6p22,
        0x1.6768df61adf8cp22,
        0x1.431ac916d8cfp19,
        -0x1.3572fbe30a5dep21,
    };
    const output = cosBinary64Vec(10, input);
    try testing.expectApproxEqAbs(0x1.fb6162de8bc4bp-1, output[0], math.floatEpsAt(f64, 0x1.fb6162de8bc4bp-1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.dbe5bf6fc26d6p-1, output[1], math.floatEpsAt(f64, -0x1.dbe5bf6fc26d6p-1) * 3.0);
    try testing.expectApproxEqAbs(0x1.30f00a1a3506cp-1, output[2], math.floatEpsAt(f64, 0x1.30f00a1a3506cp-1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.e534d1290ae45p-2, output[3], math.floatEpsAt(f64, -0x1.e534d1290ae45p-2) * 3.0);
    try testing.expectApproxEqAbs(-0x1.98367636ca60ep-1, output[4], math.floatEpsAt(f64, -0x1.98367636ca60ep-1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.379e7e54eda32p-1, output[5], math.floatEpsAt(f64, -0x1.379e7e54eda32p-1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.e3b46f77c8e4ap-1, output[6], math.floatEpsAt(f64, -0x1.e3b46f77c8e4ap-1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.b219a2845075fp-2, output[7], math.floatEpsAt(f64, -0x1.b219a2845075fp-2) * 3.0);
    try testing.expectApproxEqAbs(-0x1.6bf6b2e7a6dc4p-4, output[8], math.floatEpsAt(f64, -0x1.6bf6b2e7a6dc4p-4) * 3.0);
    try testing.expectApproxEqAbs(0x1.f82e4f8e40e12p-1, output[9], math.floatEpsAt(f64, 0x1.f82e4f8e40e12p-1) * 3.0);
}
