// Ported from ARM-software, which is licensed under the MIT license:
// https://github.com/ARM-software/optimized-routines/blob/master/LICENSE
//
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/tanf.c
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/tan.c

const std = @import("std");
const math = std.math;
const testing = std.testing;

/// Returns the tangent of x.
///
/// Special Cases:
///  - tan(+-inf) = nan
///  - tan(nan)  = nan
pub fn tan(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .float => return @tan(x),
        .vector => |info| switch (info.child) {
            f32 => return tanBinary32Vec(info.len, x),
            f64 => return tanBinary64Vec(info.len, x),
            else => @tan(x),
        },
        else => comptime unreachable,
    }
}

fn tanBinary32Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f32)) @TypeOf(x) {
    const c0: @Vector(vec_len, f32) = @splat(0x1.55555p-2);
    const c1: @Vector(vec_len, f32) = @splat(0x1.11166p-3);
    const c2: @Vector(vec_len, f32) = @splat(0x1.b88a78p-5);
    const c3: @Vector(vec_len, f32) = @splat(0x1.7b5756p-6);
    const c4: @Vector(vec_len, f32) = @splat(0x1.4ef4cep-8);
    const c5: @Vector(vec_len, f32) = @splat(0x1.0e1e74p-7);
    const neg_pio2_high: @Vector(vec_len, f32) = @splat(-0x1.921fb6p+0);
    const neg_pio2_mid: @Vector(vec_len, f32) = @splat(0x1.777a5cp-25);
    const neg_pio2_low: @Vector(vec_len, f32) = @splat(0x1.ee59dap-50);
    const inv_pio2: @Vector(vec_len, f32) = @splat(0x1.45f306p-1);
    const shift: @Vector(vec_len, f32) = @splat(0x1.8p+23);
    const range_val: @Vector(vec_len, f32) = @splat(0x1p15);
    const one: @Vector(vec_len, f32) = @splat(1.0);
    const neg_one: @Vector(vec_len, f32) = @splat(-1.0);
    const one_ui: @Vector(vec_len, u32) = @splat(1);

    const q = @mulAdd(@Vector(vec_len, f32), x, inv_pio2, shift);
    const odd = (@as(@Vector(vec_len, u32), @bitCast(q)) & one_ui) == one_ui;
    const n = q - shift;
    var r = @mulAdd(@Vector(vec_len, f32), n, neg_pio2_high, x);
    r = @mulAdd(@Vector(vec_len, f32), n, neg_pio2_mid, r);
    r = @mulAdd(@Vector(vec_len, f32), n, neg_pio2_low, r);
    const z = r * @select(f32, odd, neg_one, one);
    const z2 = r * r;
    const z3 = z2 * z;
    const z4 = z2 * z2;
    const z8 = z4 * z4;
    const p0_1 = @mulAdd(@Vector(vec_len, f32), z2, c1, c0);
    const p2_3 = @mulAdd(@Vector(vec_len, f32), z2, c3, c2);
    const p4_5 = @mulAdd(@Vector(vec_len, f32), z2, c5, c4);
    const p0_3 = @mulAdd(@Vector(vec_len, f32), z4, p2_3, p0_1);
    const p0_5 = @mulAdd(@Vector(vec_len, f32), z8, p4_5, p0_3);
    var y = @mulAdd(@Vector(vec_len, f32), z3, p0_5, z);
    y = @select(f32, odd, one / y, y);
    const special = @abs(x) >= range_val;
    if (@reduce(.Or, special)) {
        @branchHint(.unlikely);
        inline for (0..vec_len) |i| {
            if (special[i]) y[i] = @tan(x[i]);
        }
    }
    return y;
}

fn tanBinary64Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f64)) @TypeOf(x) {
    const c0: @Vector(vec_len, f64) = @splat(0x1.5555555555556p-2);
    const c1: @Vector(vec_len, f64) = @splat(0x1.1111111110a63p-3);
    const c2: @Vector(vec_len, f64) = @splat(0x1.ba1ba1bb46414p-5);
    const c3: @Vector(vec_len, f64) = @splat(0x1.664f47e5b5445p-6);
    const c4: @Vector(vec_len, f64) = @splat(0x1.226e5e5ecdfa3p-7);
    const c5: @Vector(vec_len, f64) = @splat(0x1.d6c7ddbf87047p-9);
    const c6: @Vector(vec_len, f64) = @splat(0x1.7ea75d05b583ep-10);
    const c7: @Vector(vec_len, f64) = @splat(0x1.289f22964a03cp-11);
    const c8: @Vector(vec_len, f64) = @splat(0x1.4e4fd14147622p-12);
    const neg_pio2_high: @Vector(vec_len, f64) = @splat(-0x1.921fb54442d18p0);
    const neg_pio2_low: @Vector(vec_len, f64) = @splat(-0x1.1a62633145c07p-54);
    const inv_pio2: @Vector(vec_len, f64) = @splat(0x1.45f306dc9c883p-1);
    const shift: @Vector(vec_len, f64) = @splat(0x1.8p52);
    const range_val: @Vector(vec_len, f64) = @splat(0x1p23);
    const half: @Vector(vec_len, f64) = @splat(0.5);
    const one: @Vector(vec_len, f64) = @splat(1.0);
    const neg_one: @Vector(vec_len, f64) = @splat(-1.0);
    const one_ui: @Vector(vec_len, u64) = @splat(1);

    const q = @mulAdd(@Vector(vec_len, f64), x, inv_pio2, shift);
    const odd = (@as(@Vector(vec_len, u64), @bitCast(q)) & one_ui) == one_ui;
    const n = q - shift;
    var r = @mulAdd(@Vector(vec_len, f64), n, neg_pio2_high, x);
    r = @mulAdd(@Vector(vec_len, f64), n, neg_pio2_low, r) * half;
    const z = r * @select(f64, odd, neg_one, one);
    const z2 = z * z;
    const z3 = z2 * z;
    const z4 = z2 * z2;
    const z8 = z4 * z4;
    const p1_2 = @mulAdd(@Vector(vec_len, f64), z2, c2, c1);
    const p3_4 = @mulAdd(@Vector(vec_len, f64), z2, c4, c3);
    const p1_4 = @mulAdd(@Vector(vec_len, f64), z4, p3_4, p1_2);
    const p5_6 = @mulAdd(@Vector(vec_len, f64), z2, c6, c5);
    const p7_8 = @mulAdd(@Vector(vec_len, f64), z2, c8, c7);
    const p5_8 = @mulAdd(@Vector(vec_len, f64), z4, p7_8, p5_6);
    const p1_8 = @mulAdd(@Vector(vec_len, f64), z8, p5_8, p1_4);
    const p0_8 = @mulAdd(@Vector(vec_len, f64), z2, p1_8, c0);
    const p = @mulAdd(@Vector(vec_len, f64), z3, p0_8, z);
    var y = (p + p) / @mulAdd(@Vector(vec_len, f64), p, -p, one);
    y = @select(f64, odd, one / y, y);
    const special = @abs(x) >= range_val;
    if (@reduce(.Or, special)) {
        @branchHint(.unlikely);
        inline for (0..vec_len) |i| {
            if (special[i]) y[i] = @tan(x[i]);
        }
    }
    return y;
}

test "tanBinary32Vec.special" {
    const input: @Vector(5, f32) = .{ 0x0p+0, -0x0p+0, math.inf(f32), -math.inf(f32), math.nan(f32) };
    const output = tanBinary32Vec(5, input);
    try testing.expectEqual(0x0p+0, output[0]);
    try testing.expectEqual(-0x0p+0, output[1]);
    try testing.expect(math.isNan(output[2]));
    try testing.expect(math.isNan(output[3]));
    try testing.expect(math.isNan(output[4]));
}

test "tanBinary32Vec" {
    const input: @Vector(10, f32) = .{
        0x1.b30e78p13,
        0x1.24823p15,
        -0x1.81719ep14,
        0x1.b28ccp13,
        -0x1.ff18c4p14,
        -0x1.de6c38p14,
        0x1.9306cp14,
        -0x1.92f48ap14,
        0x1.02a81p15,
        -0x1.24aadp15,
    };
    const output = tanBinary32Vec(10, input);
    try testing.expectApproxEqAbs(0x1.8e7aa8p2, output[0], math.floatEpsAt(f32, 0x1.8e7aa8p2) * 3.0);
    try testing.expectApproxEqAbs(-0x1.ba043ep-2, output[1], math.floatEpsAt(f32, -0x1.ba043ep-2) * 3.0);
    try testing.expectApproxEqAbs(-0x1.6c9476p-1, output[2], math.floatEpsAt(f32, -0x1.6c9476p-1) * 3.0);
    try testing.expectApproxEqAbs(0x1.45b5aap0, output[3], math.floatEpsAt(f32, 0x1.45b5aap0) * 3.0);
    try testing.expectApproxEqAbs(0x1.248d8p-4, output[4], math.floatEpsAt(f32, 0x1.248d8p-4) * 3.0);
    try testing.expectApproxEqAbs(-0x1.ee01a8p0, output[5], math.floatEpsAt(f32, -0x1.ee01a8p0) * 3.0);
    try testing.expectApproxEqAbs(0x1.551d1ep1, output[6], math.floatEpsAt(f32, 0x1.551d1ep1) * 3.0);
    try testing.expectApproxEqAbs(0x1.9db786p-3, output[7], math.floatEpsAt(f32, 0x1.9db786p-3) * 3.0);
    try testing.expectApproxEqAbs(-0x1.571b5ep1, output[8], math.floatEpsAt(f32, -0x1.571b5ep1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.c3fa0ep0, output[9], math.floatEpsAt(f32, -0x1.c3fa0ep0) * 3.0);
}

test "tanBinary64Vec.special" {
    const input: @Vector(5, f64) = .{ 0x0p+0, -0x0p+0, math.inf(f64), -math.inf(f64), math.nan(f64) };
    const output = tanBinary64Vec(5, input);
    try testing.expectEqual(0x0p+0, output[0]);
    try testing.expectEqual(-0x0p+0, output[1]);
    try testing.expect(math.isNan(output[2]));
    try testing.expect(math.isNan(output[3]));
    try testing.expect(math.isNan(output[4]));
}

test "tanBinary64Vec" {
    const input: @Vector(10, f64) = .{
        -0x1.e97e5f309de22p22,
        -0x1.df9d9078d00ap18,
        0x1.d0cd80ac0e28p17,
        0x1.26868c6614744p21,
        -0x1.ac468fe010295p22,
        0x1.943b8ec65a676p22,
        -0x1.e740d5931bc44p20,
        0x1.3e7df345a0acp20,
        0x1.09ff5fab3c26cp21,
        0x1.cc32977b62498p21,
    };
    const output = tanBinary64Vec(10, input);
    try testing.expectApproxEqAbs(0x1.b85aa3713006fp-3, output[0], math.floatEpsAt(f64, 0x1.b85aa3713006fp-3) * 3.0);
    try testing.expectApproxEqAbs(-0x1.dc8ce64f6c6b3p0, output[1], math.floatEpsAt(f64, -0x1.dc8ce64f6c6b3p0) * 3.0);
    try testing.expectApproxEqAbs(0x1.ca4acdcd3b22fp-3, output[2], math.floatEpsAt(f64, 0x1.ca4acdcd3b22fp-3) * 3.0);
    try testing.expectApproxEqAbs(0x1.733fc37d8aed2p0, output[3], math.floatEpsAt(f64, 0x1.733fc37d8aed2p0) * 3.0);
    try testing.expectApproxEqAbs(-0x1.6b75ed1c8423ep2, output[4], math.floatEpsAt(f64, -0x1.6b75ed1c8423ep2) * 3.0);
    try testing.expectApproxEqAbs(-0x1.28bbf7d5725c3p0, output[5], math.floatEpsAt(f64, -0x1.28bbf7d5725c3p0) * 3.0);
    try testing.expectApproxEqAbs(-0x1.02bbc68f59f68p4, output[6], math.floatEpsAt(f64, -0x1.02bbc68f59f68p4) * 3.0);
    try testing.expectApproxEqAbs(-0x1.b20e77afe33b8p-9, output[7], math.floatEpsAt(f64, -0x1.b20e77afe33b8p-9) * 3.0);
    try testing.expectApproxEqAbs(-0x1.a509f677ceb3cp-1, output[8], math.floatEpsAt(f64, -0x1.a509f677ceb3cp-1) * 3.0);
    try testing.expectApproxEqAbs(-0x1.2776f244bb304p-1, output[9], math.floatEpsAt(f64, -0x1.2776f244bb304p-1) * 3.0);
}
