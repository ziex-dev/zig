const std = @import("../../std.zig");
const math = std.math;
const mem = std.mem;

const Limb = std.math.big.Limb;
const DoubleLimb = std.math.big.DoubleLimb;
const HalfLimb = std.math.big.HalfLimb;
const Log2Limb = std.math.big.Log2Limb;
const limb_bits = @typeInfo(Limb).int.bits;
const half_limb_bits = @typeInfo(HalfLimb).int.bits;

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const maxInt = math.maxInt;

fn slicesOverlap(a: []const Limb, b: []const Limb) bool {
    // there is no overlap if a.ptr + a.len <= b.ptr or b.ptr + b.len <= a.ptr
    return @intFromPtr(a.ptr + a.len) > @intFromPtr(b.ptr) and @intFromPtr(b.ptr + b.len) > @intFromPtr(a.ptr);
}

/// Different operators which can be used in accumulation style functions
/// (llmulacc, llmulaccKaratsuba, llmulaccLong, llmulLimb). In all these functions,
/// a computed value is accumulated with an existing result.
pub const AccOp = enum {
    /// The computed value is added to the result.
    add,

    /// The computed value is subtracted from the result.
    sub,
};

/// Knuth 4.3.1, Algorithm M.
///
/// r = r (op) a * b
/// r MUST NOT alias any of a or b.
///
/// The result is computed modulo `r.len`. When `r.len >= a.len + b.len`, no overflow occurs.
pub fn llmulacc(comptime op: AccOp, opt_allocator: ?Allocator, r: []Limb, a: []const Limb, b: []const Limb) void {
    assert(r.len >= a.len);
    assert(r.len >= b.len);
    assert(!slicesOverlap(r, a));
    assert(!slicesOverlap(r, b));

    // Order greatest first.
    var x = a;
    var y = b;
    if (a.len < b.len) {
        x = b;
        y = a;
    }

    k_mul: {
        if (y.len > 48) {
            if (opt_allocator) |allocator| {
                llmulaccKaratsuba(op, allocator, r, x, y) catch |err| switch (err) {
                    error.OutOfMemory => break :k_mul, // handled below
                };
                return;
            }
        }
    }

    llmulaccLong(op, r, x, y);
}

/// Knuth 4.3.1, Algorithm M.
///
/// r = r (op) a * b
/// r MUST NOT alias any of a or b.
///
/// The result is computed modulo `r.len`. When `r.len >= a.len + b.len`, no overflow occurs.
pub fn llmulaccKaratsuba(
    comptime op: AccOp,
    allocator: Allocator,
    r: []Limb,
    a: []const Limb,
    b: []const Limb,
) error{OutOfMemory}!void {
    assert(r.len >= a.len);
    assert(a.len >= b.len);
    assert(!slicesOverlap(r, a));
    assert(!slicesOverlap(r, b));

    // Classical karatsuba algorithm:
    // a = a1 * B + a0
    // b = b1 * B + b0
    // Where a0, b0 < B
    //
    // We then have:
    // ab = a * b
    //    = (a1 * B + a0) * (b1 * B + b0)
    //    = a1 * b1 * B * B + a1 * B * b0 + a0 * b1 * B + a0 * b0
    //    = a1 * b1 * B * B + (a1 * b0 + a0 * b1) * B + a0 * b0
    //
    // Note that:
    // a1 * b0 + a0 * b1
    //    = (a1 + a0)(b1 + b0) - a1 * b1 - a0 * b0
    //    = (a0 - a1)(b1 - b0) + a1 * b1 + a0 * b0
    //
    // This yields:
    // ab = p2 * B^2 + (p0 + p1 + p2) * B + p0
    //
    // Where:
    // p0 = a0 * b0
    // p1 = (a0 - a1)(b1 - b0)
    // p2 = a1 * b1
    //
    // Note, (a0 - a1) and (b1 - b0) produce values -B < x < B, and so we need to mind the sign here.
    // We also have:
    // 0 <= p0 <= 2B
    // -2B <= p1 <= 2B
    //
    // Note, when B is a multiple of the limb size, multiplies by B amount to shifts or
    // slices of a limbs array.
    //
    // This function computes the result of the multiplication modulo r.len. This means:
    // - p2 and p1 only need to be computed modulo r.len - B.
    // - In the case of p2, p2 * B^2 needs to be added modulo r.len - 2 * B.

    const split = b.len / 2; // B

    const limbs_after_split = r.len - split; // Limbs to compute for p1 and p2.
    const limbs_after_split2 = r.len - split * 2; // Limbs to add for p2 * B^2.

    // For a0 and b0 we need the full range.
    const a0 = a[0..llnormalize(a[0..split])];
    const b0 = b[0..llnormalize(b[0..split])];

    // For a1 and b1 we only need `limbs_after_split` limbs.
    const a1 = blk: {
        var a1 = a[split..];
        a1.len = @min(llnormalize(a1), limbs_after_split);
        break :blk a1;
    };

    const b1 = blk: {
        var b1 = b[split..];
        b1.len = @min(llnormalize(b1), limbs_after_split);
        break :blk b1;
    };

    // Note that the above slices relative to `split` work because we have a.len > b.len.

    // We need some temporary memory to store intermediate results.
    // Note, we can reduce the amount of temporaries we need by reordering the computation here:
    // ab = p2 * B^2 + (p0 + p1 + p2) * B + p0
    //    = p2 * B^2 + (p0 * B + p1 * B + p2 * B) + p0
    //    = (p2 * B^2 + p2 * B) + (p0 * B + p0) + p1 * B

    // Allocate at least enough memory to be able to multiply the upper two segments of a and b, assuming
    // no overflow.
    const tmp = try allocator.alloc(Limb, a.len - split + b.len - split);
    defer allocator.free(tmp);

    // Compute p2.
    // Note, we don't need to compute all of p2, just enough limbs to satisfy r.
    const p2_limbs = @min(limbs_after_split, a1.len + b1.len);

    @memset(tmp[0..p2_limbs], 0);
    llmulacc(.add, allocator, tmp[0..p2_limbs], a1[0..@min(a1.len, p2_limbs)], b1[0..@min(b1.len, p2_limbs)]);
    const p2 = tmp[0..llnormalize(tmp[0..p2_limbs])];

    // Add p2 * B to the result.
    llaccum(op, r[split..], p2);

    // Add p2 * B^2 to the result if required.
    if (limbs_after_split2 > 0) {
        llaccum(op, r[split * 2 ..], p2[0..@min(p2.len, limbs_after_split2)]);
    }

    // Compute p0.
    // Since a0.len, b0.len <= split and r.len >= split * 2, the full width of p0 needs to be computed.
    const p0_limbs = a0.len + b0.len;
    @memset(tmp[0..p0_limbs], 0);
    llmulacc(.add, allocator, tmp[0..p0_limbs], a0, b0);
    const p0 = tmp[0..llnormalize(tmp[0..p0_limbs])];

    // Add p0 to the result.
    llaccum(op, r, p0);

    // Add p0 * B to the result. In this case, we may not need all of it.
    llaccum(op, r[split..], p0[0..@min(limbs_after_split, p0.len)]);

    // Finally, compute and add p1.
    // From now on we only need `limbs_after_split` limbs for a0 and b0, since the result of the
    // following computation will be added * B.
    const a0x = a0[0..@min(a0.len, limbs_after_split)];
    const b0x = b0[0..@min(b0.len, limbs_after_split)];

    const j0_sign = llcmp(a0x, a1);
    const j1_sign = llcmp(b1, b0x);

    if (j0_sign * j1_sign == 0) {
        // p1 is zero, we don't need to do any computation at all.
        return;
    }

    @memset(tmp, 0);

    // p1 is nonzero, so compute the intermediary terms j0 = a0 - a1 and j1 = b1 - b0.
    // Note that in this case, we again need some storage for intermediary results
    // j0 and j1. Since we have tmp.len >= 2B, we can store both
    // intermediaries in the already allocated array.
    const j0 = tmp[0 .. a.len - split];
    const j1 = tmp[a.len - split ..];

    // Ensure that no subtraction overflows.
    if (j0_sign == 1) {
        // a0 > a1.
        _ = llopcarry(.sub, j0, a0x, a1);
    } else {
        // a0 < a1.
        _ = llopcarry(.sub, j0, a1, a0x);
    }

    if (j1_sign == 1) {
        // b1 > b0.
        _ = llopcarry(.sub, j1, b1, b0x);
    } else {
        // b1 > b0.
        _ = llopcarry(.sub, j1, b0x, b1);
    }

    if (j0_sign * j1_sign == 1) {
        // If j0 and j1 are both positive, we now have:
        // p1 = j0 * j1
        // If j0 and j1 are both negative, we now have:
        // p1 = -j0 * -j1 = j0 * j1
        // In this case we can add p1 to the result using llmulacc.
        llmulacc(op, allocator, r[split..], j0[0..llnormalize(j0)], j1[0..llnormalize(j1)]);
    } else {
        // In this case either j0 or j1 is negative, an we have:
        // p1 = -(j0 * j1)
        // Now we need to subtract instead of accumulate.
        const inverted_op = if (op == .add) .sub else .add;
        llmulacc(inverted_op, allocator, r[split..], j0[0..llnormalize(j0)], j1[0..llnormalize(j1)]);
    }
}

/// r = r (op) a.
/// The result is computed modulo `r.len`.
pub fn llaccum(comptime op: AccOp, r: []Limb, a: []const Limb) void {
    assert(!slicesOverlap(r, a) or @intFromPtr(r.ptr) <= @intFromPtr(a.ptr));
    _ = llopcarry(op, r, r, a);
}

/// Returns -1, 0, 1 if |a| < |b|, |a| == |b| or |a| > |b| respectively for limbs.
pub fn llcmp(a: []const Limb, b: []const Limb) i8 {
    const a_len = llnormalize(a);
    const b_len = llnormalize(b);
    if (a_len < b_len) {
        return -1;
    }
    if (a_len > b_len) {
        return 1;
    }

    var i: usize = a_len - 1;
    while (i != 0) : (i -= 1) {
        if (a[i] != b[i]) {
            break;
        }
    }

    if (a[i] < b[i]) {
        return -1;
    } else if (a[i] > b[i]) {
        return 1;
    } else {
        return 0;
    }
}

/// r = r (op) y * xi
/// The result is computed modulo `r.len`. When `r.len >= a.len + b.len`, no overflow occurs.
pub fn llmulaccLong(comptime op: AccOp, r: []Limb, a: []const Limb, b: []const Limb) void {
    assert(r.len >= a.len);
    assert(a.len >= b.len);

    var i: usize = 0;
    while (i < b.len) : (i += 1) {
        _ = llmulLimb(op, r[i..], a, b[i]);
    }
}

/// Performs a (op) b (op) carry, and also returns the carry if any.
/// Can be lowered to `adc` / `sbb` instructions on x86_64.
fn opWithCarry(comptime op: AccOp, a: Limb, b: Limb, carry: Limb) struct { Limb, Limb } {
    const res1, const c1 = opWithOverflow(op, a, b);
    const res2, const c2 = opWithOverflow(op, res1, carry);
    assert((c1 & c2) == 0);
    return .{ res2, c1 | c2 };
}

fn mulWide(a: Limb, b: Limb) struct { Limb, Limb } {
    const prod = math.mulWide(Limb, a, b);
    return .{ @truncate(prod), @truncate(prod >> limb_bits) };
}

/// r = r (op) y * xi
/// The result is computed modulo `r.len`.
/// Returns whether the operation overflowed.
pub fn llmulLimb(comptime op: AccOp, acc: []Limb, y: []const Limb, xi: Limb) bool {
    assert(!slicesOverlap(acc, y) or @intFromPtr(acc.ptr) <= @intFromPtr(y.ptr));

    if (xi == 0) {
        return false;
    }

    const split = @min(y.len, acc.len);
    var a_lo = acc[0..split];
    var a_hi = acc[split..];

    var j: usize = 0;

    var carry: Limb = 0;
    var old_cc4: Limb = 0;
    // temporary results
    var r1: Limb = undefined;
    var r2: Limb = undefined;
    var r3: Limb = undefined;
    var r4: Limb = undefined;

    for (0..(split % 4)) |_| {
        const p1_lo, const p1_hi = mulWide(y[j], xi);
        const res, const cc = opWithCarry(op, acc[j], p1_lo, old_cc4);
        acc[j], old_cc4 = opWithOverflow(op, res, carry);
        carry, const cc2 = opWithOverflow(.add, p1_hi, cc);
        assert(cc2 == 0);

        j += 1;
    }

    if (split >= 4) {
        {
            const p1_lo, const p1_hi = mulWide(y[j + 0], xi);
            const p2_lo, const p2_hi = mulWide(y[j + 1], xi);
            const p3_lo, const p3_hi = mulWide(y[j + 2], xi);

            r1, const c1 = opWithCarry(.add, p1_lo, carry, old_cc4);
            const p4_lo, const p4_hi = mulWide(y[j + 3], xi);

            r2, const c2 = opWithCarry(.add, p1_hi, p2_lo, c1);
            r3, const c3 = opWithCarry(.add, p2_hi, p3_lo, c2);
            r4, const c4 = opWithCarry(.add, p3_hi, p4_lo, c3);

            carry, const c5 = opWithCarry(.add, p4_hi, 0, c4);
            assert(c5 == 0);
        }

        // This implementation has been made to generate nearly the same
        // assembly as one of gmp's implementation for `addmul_1`
        // (see mpn/x86_64/zen/aorsmul_1.asm in gmp's sources)
        while (j + 8 <= a_lo.len) : (j += 4) {
            a_lo[j], const cc1 = opWithOverflow(op, a_lo[j], r1);
            const p1_lo, const p1_hi = mulWide(y[j + 4], xi);
            a_lo[j + 1], const cc2 = opWithCarry(op, a_lo[j + 1], r2, cc1);
            const p2_lo, const p2_hi = mulWide(y[j + 5], xi);
            a_lo[j + 2], const cc3 = opWithCarry(op, a_lo[j + 2], r3, cc2);
            const p3_lo, const p3_hi = mulWide(y[j + 6], xi);
            a_lo[j + 3], const cc4 = opWithCarry(op, a_lo[j + 3], r4, cc3);

            r1, const c1 = opWithCarry(.add, p1_lo, carry, cc4);
            const p4_lo, const p4_hi = mulWide(y[j + 7], xi);

            r2, const c2 = opWithCarry(.add, p1_hi, p2_lo, c1);
            r3, const c3 = opWithCarry(.add, p2_hi, p3_lo, c2);
            r4, const c4 = opWithCarry(.add, p3_hi, p4_lo, c3);

            carry, const c5 = opWithCarry(.add, p4_hi, 0, c4);
            assert(c5 == 0);
        }
        a_lo[j + 0], const cc1 = opWithOverflow(op, a_lo[j + 0], r1);
        a_lo[j + 1], const cc2 = opWithCarry(op, a_lo[j + 1], r2, cc1);
        a_lo[j + 2], const cc3 = opWithCarry(op, a_lo[j + 2], r3, cc2);
        a_lo[j + 3], const cc4 = opWithCarry(op, a_lo[j + 3], r4, cc3);

        carry += cc4;
    } else {
        carry += old_cc4;
    }

    j = 0;
    while ((carry != 0) and (j < a_hi.len)) : (j += 1) {
        a_hi[j], carry = opWithOverflow(op, a_hi[j], carry);
    }

    return carry != 0;
}

/// a + b * c + *carry, sets carry to the overflow bits
pub fn addMulLimbWithCarry(a: Limb, b: Limb, c: Limb, carry: *Limb) Limb {
    // ov1[0] = a + *carry
    const ov1 = opWithOverflow(.add, a, carry.*);

    // r2 = b * c
    const bc = @as(DoubleLimb, math.mulWide(Limb, b, c));
    const r2 = @as(Limb, @truncate(bc));
    const c2 = @as(Limb, @truncate(bc >> limb_bits));

    // ov2[0] = ov1[0] + r2
    const ov2 = opWithOverflow(.add, ov1[0], r2);

    // This never overflows, c1, c3 are either 0 or 1 and if both are 1 then
    // c2 is at least <= maxInt(Limb) - 2.
    carry.* = ov1[1] + c2 + ov2[1];

    return ov2[0];
}

/// a - b * c - *carry, sets carry to the overflow bits
pub fn subMulLimbWithBorrow(a: Limb, b: Limb, c: Limb, carry: *Limb) Limb {
    // ov1[0] = a - *carry
    const ov1 = opWithOverflow(.sub, a, carry.*);

    // r2 = b * c
    const bc = @as(DoubleLimb, std.math.mulWide(Limb, b, c));
    const r2 = @as(Limb, @truncate(bc));
    const c2 = @as(Limb, @truncate(bc >> limb_bits));

    // ov2[0] = ov1[0] - r2
    const ov2 = opWithOverflow(.sub, ov1[0], r2);
    carry.* = ov1[1] + c2 + ov2[1];

    return ov2[0];
}

/// returns the min length the limb could be.
pub fn llnormalize(a: []const Limb) usize {
    var j = a.len;
    while (j > 0) : (j -= 1) {
        if (a[j - 1] != 0) {
            break;
        }
    }

    // Handle zero
    return if (j != 0) j else 1;
}

// This function is a workaround around #17391
// It allows llvm to produce better code (at least on x86_64),
// by avoiding `u1` for the carry
pub fn opWithOverflow(comptime op: AccOp, a: Limb, b: Limb) struct { Limb, Limb } {
    const res = switch (op) {
        .add => a +% b,
        .sub => a -% b,
    };
    const cond = switch (op) {
        // "res < a" does not produce good code, for some reason
        .add => res < b,
        .sub => a < b,
    };
    return .{ res, if (cond) 1 else 0 };
}

/// Knuth 4.3.1, Algorithm A and S.
pub fn llopcarry(comptime op: AccOp, r: []Limb, a: []const Limb, b: []const Limb) Limb {
    assert(a.len != 0 and b.len != 0);
    assert(a.len >= b.len);
    assert(r.len >= a.len);
    assert(!slicesOverlap(r, a) or @intFromPtr(r.ptr) <= @intFromPtr(a.ptr));
    assert(!slicesOverlap(r, b) or @intFromPtr(r.ptr) <= @intFromPtr(b.ptr));

    var i: usize = 0;
    var carry: Limb = 0;

    while (i < b.len) : (i += 1) {
        r[i], carry = opWithCarry(op, a[i], b[i], carry);
    }

    while (i < a.len) : (i += 1) {
        r[i], carry = opWithOverflow(op, a[i], carry);
    }

    return carry;
}

/// Knuth 4.3.1, Exercise 16.
pub fn lldiv1(quo: []Limb, rem: *Limb, a: []const Limb, b: Limb) void {
    assert(a.len > 0);
    assert(quo.len >= a.len);

    rem.* = 0;
    for (a, 0..) |_, ri| {
        const i = a.len - ri - 1;
        const pdiv = ((@as(DoubleLimb, rem.*) << limb_bits) | a[i]);

        if (pdiv == 0) {
            quo[i] = 0;
            rem.* = 0;
        } else if (pdiv < b) {
            quo[i] = 0;
            rem.* = @as(Limb, @truncate(pdiv));
        } else if (pdiv == b) {
            quo[i] = 1;
            rem.* = 0;
        } else {
            quo[i] = @as(Limb, @truncate(@divTrunc(pdiv, b)));
            rem.* = @as(Limb, @truncate(pdiv - (quo[i] *% b)));
        }
    }
}

pub fn lldiv0p5(quo: []Limb, rem: *Limb, a: []const Limb, b: HalfLimb) void {
    assert(a.len > 1 or a[0] >= b);
    assert(quo.len >= a.len);

    rem.* = 0;
    for (a, 0..) |_, ri| {
        const i = a.len - ri - 1;
        const ai_high = a[i] >> half_limb_bits;
        const ai_low = a[i] & ((1 << half_limb_bits) - 1);

        // Split the division into two divisions acting on half a limb each. Carry remainder.
        const ai_high_with_carry = (rem.* << half_limb_bits) | ai_high;
        const ai_high_quo = ai_high_with_carry / b;
        rem.* = ai_high_with_carry % b;

        const ai_low_with_carry = (rem.* << half_limb_bits) | ai_low;
        const ai_low_quo = ai_low_with_carry / b;
        rem.* = ai_low_with_carry % b;

        quo[i] = (ai_high_quo << half_limb_bits) | ai_low_quo;
    }
}

/// Performs r = a << shift and returns the amount of limbs affected
///
/// if a and r overlaps, then r.ptr >= a.ptr is asserted
/// r must have the capacity to store a << shift
pub fn llshl(r: []Limb, a: []const Limb, shift: usize) usize {
    std.debug.assert(a.len >= 1);
    if (slicesOverlap(a, r))
        std.debug.assert(@intFromPtr(r.ptr) >= @intFromPtr(a.ptr));

    if (shift == 0) {
        if (a.ptr != r.ptr) @memmove(r[0..a.len], a);
        return a.len;
    }
    if (shift >= limb_bits) {
        const limb_shift = shift / limb_bits;

        const affected = llshl(r[limb_shift..], a, shift % limb_bits);
        @memset(r[0..limb_shift], 0);

        return limb_shift + affected;
    }

    // shift is guaranteed to be < limb_bits
    const bit_shift: Log2Limb = @truncate(shift);
    const opposite_bit_shift: Log2Limb = @truncate(limb_bits - bit_shift);

    // We only need the extra limb if the shift of the last element overflows.
    // This is useful for the implementation of `shiftLeftSat`.
    const overflows = a[a.len - 1] >> opposite_bit_shift != 0;
    if (overflows) {
        std.debug.assert(r.len >= a.len + 1);
    } else {
        std.debug.assert(r.len >= a.len);
    }

    var i: usize = a.len;
    if (overflows) {
        // r is asserted to be large enough above
        r[a.len] = a[a.len - 1] >> opposite_bit_shift;
    }
    while (i > 1) {
        i -= 1;
        r[i] = (a[i - 1] >> opposite_bit_shift) | (a[i] << bit_shift);
    }
    r[0] = a[0] << bit_shift;

    return a.len + @intFromBool(overflows);
}

/// Performs r = a >> shift and returns the amount of limbs affected
///
/// if a and r overlaps, then r.ptr <= a.ptr is asserted
/// r must have the capacity to store a >> shift
///
/// See tests below for examples of behaviour
pub fn llshr(r: []Limb, a: []const Limb, shift: usize) usize {
    if (slicesOverlap(a, r))
        std.debug.assert(@intFromPtr(r.ptr) <= @intFromPtr(a.ptr));

    if (a.len == 0) return 0;

    if (shift == 0) {
        std.debug.assert(r.len >= a.len);

        if (a.ptr != r.ptr) @memmove(r[0..a.len], a);
        return a.len;
    }
    if (shift >= limb_bits) {
        if (shift / limb_bits >= a.len) {
            r[0] = 0;
            return 1;
        }
        return llshr(r, a[shift / limb_bits ..], shift % limb_bits);
    }

    // shift is guaranteed to be < limb_bits
    const bit_shift: Log2Limb = @truncate(shift);
    const opposite_bit_shift: Log2Limb = @truncate(limb_bits - bit_shift);

    // special case, where there is a risk to set r to 0
    if (a.len == 1) {
        r[0] = a[0] >> bit_shift;
        return 1;
    }
    if (a.len == 0) {
        r[0] = 0;
        return 1;
    }

    // if the most significant limb becomes 0 after the shift
    const shrink = a[a.len - 1] >> bit_shift == 0;
    std.debug.assert(r.len >= a.len - @intFromBool(shrink));

    var i: usize = 0;
    while (i < a.len - 1) : (i += 1) {
        r[i] = (a[i] >> bit_shift) | (a[i + 1] << opposite_bit_shift);
    }

    if (!shrink)
        r[i] = a[i] >> bit_shift;

    return a.len - @intFromBool(shrink);
}

// r = ~r
pub fn llnot(r: []Limb) void {
    for (r) |*elem| {
        elem.* = ~elem.*;
    }
}

// r = a | b with 2s complement semantics.
// r may alias.
// a and b must not be 0.
// Returns `true` when the result is positive.
// When b is positive, r requires at least `a.len` limbs of storage.
// When b is negative, r requires at least `b.len` limbs of storage.
pub fn llsignedor(r: []Limb, a: []const Limb, a_positive: bool, b: []const Limb, b_positive: bool) bool {
    assert(r.len >= a.len);
    assert(a.len >= b.len);

    if (a_positive and b_positive) {
        // Trivial case, result is positive.
        var i: usize = 0;
        while (i < b.len) : (i += 1) {
            r[i] = a[i] | b[i];
        }
        while (i < a.len) : (i += 1) {
            r[i] = a[i];
        }

        return true;
    } else if (!a_positive and b_positive) {
        // Result is negative.
        // r = (--a) | b
        //   = ~(-a - 1) | b
        //   = ~(-a - 1) | ~~b
        //   = ~((-a - 1) & ~b)
        //   = -(((-a - 1) & ~b) + 1)

        var i: usize = 0;
        var a_borrow: Limb = 1;
        var r_carry: Limb = 1;

        while (i < b.len) : (i += 1) {
            const ov1 = opWithOverflow(.sub, a[i], a_borrow);
            a_borrow = ov1[1];
            const ov2 = opWithOverflow(.add, ov1[0] & ~b[i], r_carry);
            r[i] = ov2[0];
            r_carry = ov2[1];
        }

        // In order for r_carry to be nonzero at this point, ~b[i] would need to be
        // all ones, which would require b[i] to be zero. This cannot be when
        // b is normalized, so there cannot be a carry here.
        // Also, x & ~b can only clear bits, so (x & ~b) <= x, meaning (-a - 1) + 1 never overflows.
        assert(r_carry == 0);

        // With b = 0, we get (-a - 1) & ~0 = -a - 1.
        // Note, if a_borrow is zero we do not need to compute anything for
        // the higher limbs so we can early return here.
        while (i < a.len and a_borrow == 1) : (i += 1) {
            const ov = opWithOverflow(.sub, a[i], a_borrow);
            r[i] = ov[0];
            a_borrow = ov[1];
        }

        assert(a_borrow == 0); // a was 0.

        return false;
    } else if (a_positive and !b_positive) {
        // Result is negative.
        // r = a | (--b)
        //   = a | ~(-b - 1)
        //   = ~~a | ~(-b - 1)
        //   = ~(~a & (-b - 1))
        //   = -((~a & (-b - 1)) + 1)

        var i: usize = 0;
        var b_borrow: Limb = 1;
        var r_carry: Limb = 1;

        while (i < b.len) : (i += 1) {
            const ov1 = opWithOverflow(.sub, b[i], b_borrow);
            b_borrow = ov1[1];
            const ov2 = opWithOverflow(.add, ~a[i] & ov1[0], r_carry);
            r[i] = ov2[0];
            r_carry = ov2[1];
        }

        // b is at least 1, so this should never underflow.
        assert(b_borrow == 0); // b was 0

        // x & ~a can only clear bits, so (x & ~a) <= x, meaning (-b - 1) + 1 never overflows.
        assert(r_carry == 0);

        // With b = 0 and b_borrow = 0, we get ~a & (0 - 0) = ~a & 0 = 0.
        // Omit setting the upper bytes, just deal with those when calling llsignedor.

        return false;
    } else {
        // Result is negative.
        // r = (--a) | (--b)
        //   = ~(-a - 1) | ~(-b - 1)
        //   = ~((-a - 1) & (-b - 1))
        //   = -(~(~((-a - 1) & (-b - 1))) + 1)
        //   = -((-a - 1) & (-b - 1) + 1)

        var i: usize = 0;
        var a_borrow: Limb = 1;
        var b_borrow: Limb = 1;
        var r_carry: Limb = 1;

        while (i < b.len) : (i += 1) {
            const ov1 = opWithOverflow(.sub, a[i], a_borrow);
            a_borrow = ov1[1];
            const ov2 = opWithOverflow(.sub, b[i], b_borrow);
            b_borrow = ov2[1];
            const ov3 = opWithOverflow(.add, ov1[0] & ov2[0], r_carry);
            r[i] = ov3[0];
            r_carry = ov3[1];
        }

        // b is at least 1, so this should never underflow.
        assert(b_borrow == 0); // b was 0

        // Can never overflow because in order for b_limb to be maxInt(Limb),
        // b_borrow would need to equal 1.

        // x & y can only clear bits, meaning x & y <= x and x & y <= y. This implies that
        // for x = a - 1 and y = b - 1, the +1 term would never cause an overflow.
        assert(r_carry == 0);

        // With b = 0 and b_borrow = 0 we get (-a - 1) & (0 - 0) = (-a - 1) & 0 = 0.
        // Omit setting the upper bytes, just deal with those when calling llsignedor.
        return false;
    }
}

// r = a & b with 2s complement semantics.
// r may alias.
// a and b must not be 0.
// Returns `true` when the result is positive.
// We assume `a.len >= b.len` here, so:
// 1. when b is positive, r requires at least `b.len` limbs of storage,
// 2. when b is negative but a is positive, r requires at least `a.len` limbs of storage,
// 3. when both a and b are negative, r requires at least `a.len + 1` limbs of storage.
pub fn llsignedand(r: []Limb, a: []const Limb, a_positive: bool, b: []const Limb, b_positive: bool) bool {
    assert(a.len != 0 and b.len != 0);
    assert(a.len >= b.len);
    assert(r.len >= if (b_positive) b.len else if (a_positive) a.len else a.len + 1);

    if (a_positive and b_positive) {
        // Trivial case, result is positive.
        var i: usize = 0;
        while (i < b.len) : (i += 1) {
            r[i] = a[i] & b[i];
        }

        // With b = 0 we have a & 0 = 0, so the upper bytes are zero.
        // Omit setting them here and simply discard them whenever
        // llsignedand is called.

        return true;
    } else if (!a_positive and b_positive) {
        // Result is positive.
        // r = (--a) & b
        //   = ~(-a - 1) & b

        var i: usize = 0;
        var a_borrow: Limb = 1;

        while (i < b.len) : (i += 1) {
            const ov = opWithOverflow(.sub, a[i], a_borrow);
            a_borrow = ov[1];
            r[i] = ~ov[0] & b[i];
        }

        // With b = 0 we have ~(a - 1) & 0 = 0, so the upper bytes are zero.
        // Omit setting them here and simply discard them whenever
        // llsignedand is called.

        return true;
    } else if (a_positive and !b_positive) {
        // Result is positive.
        // r = a & (--b)
        //   = a & ~(-b - 1)

        var i: usize = 0;
        var b_borrow: Limb = 1;

        while (i < b.len) : (i += 1) {
            const ov = opWithOverflow(.sub, b[i], b_borrow);
            b_borrow = ov[1];
            r[i] = a[i] & ~ov[0];
        }

        assert(b_borrow == 0); // b was 0

        // With b = 0 and b_borrow = 0 we have a & ~(0 - 0) = a & ~0 = a, so
        // the upper bytes are the same as those of a.

        while (i < a.len) : (i += 1) {
            r[i] = a[i];
        }

        return true;
    } else {
        // Result is negative.
        // r = (--a) & (--b)
        //   = ~(-a - 1) & ~(-b - 1)
        //   = ~((-a - 1) | (-b - 1))
        //   = -(((-a - 1) | (-b - 1)) + 1)

        var i: usize = 0;
        var a_borrow: Limb = 1;
        var b_borrow: Limb = 1;
        var r_carry: Limb = 1;

        while (i < b.len) : (i += 1) {
            const ov1 = opWithOverflow(.sub, a[i], a_borrow);
            a_borrow = ov1[1];
            const ov2 = opWithOverflow(.sub, b[i], b_borrow);
            b_borrow = ov2[1];
            const ov3 = opWithOverflow(.add, ov1[0] | ov2[0], r_carry);
            r[i] = ov3[0];
            r_carry = ov3[1];
        }

        // b is at least 1, so this should never underflow.
        assert(b_borrow == 0); // b was 0

        // With b = 0 and b_borrow = 0 we get (-a - 1) | (0 - 0) = (-a - 1) | 0 = -a - 1.
        while (i < a.len) : (i += 1) {
            const ov1 = opWithOverflow(.sub, a[i], a_borrow);
            a_borrow = ov1[1];
            const ov2 = opWithOverflow(.add, ov1[0], r_carry);
            r[i] = ov2[0];
            r_carry = ov2[1];
        }

        assert(a_borrow == 0); // a was 0.

        // The final addition can overflow here, so we need to keep that in mind.
        r[i] = r_carry;

        return false;
    }
}

// r = a ^ b with 2s complement semantics.
// r may alias.
// a and b must not be -0.
// Returns `true` when the result is positive.
// If the sign of a and b is equal, then r requires at least `@max(a.len, b.len)` limbs are required.
// Otherwise, r requires at least `@max(a.len, b.len) + 1` limbs.
pub fn llsignedxor(r: []Limb, a: []const Limb, a_positive: bool, b: []const Limb, b_positive: bool) bool {
    assert(a.len != 0 and b.len != 0);
    assert(r.len >= a.len);
    assert(a.len >= b.len);

    // If a and b are positive, the result is positive and r = a ^ b.
    // If a negative, b positive, result is negative and we have
    // r = --(--a ^ b)
    //   = --(~(-a - 1) ^ b)
    //   = -(~(~(-a - 1) ^ b) + 1)
    //   = -(((-a - 1) ^ b) + 1)
    // Same if a is positive and b is negative, sides switched.
    // If both a and b are negative, the result is positive and we have
    // r = (--a) ^ (--b)
    //   = ~(-a - 1) ^ ~(-b - 1)
    //   = (-a - 1) ^ (-b - 1)
    // These operations can be made more generic as follows:
    // - If a is negative, subtract 1 from |a| before the xor.
    // - If b is negative, subtract 1 from |b| before the xor.
    // - if the result is supposed to be negative, add 1.

    var i: usize = 0;
    var a_borrow: Limb = @intFromBool(!a_positive);
    var b_borrow: Limb = @intFromBool(!b_positive);
    var r_carry: Limb = @intFromBool(a_positive != b_positive);

    while (i < b.len) : (i += 1) {
        const ov1 = opWithOverflow(.sub, a[i], a_borrow);
        a_borrow = ov1[1];
        const ov2 = opWithOverflow(.sub, b[i], b_borrow);
        b_borrow = ov2[1];
        const ov3 = opWithOverflow(.add, ov1[0] ^ ov2[0], r_carry);
        r[i] = ov3[0];
        r_carry = ov3[1];
    }

    while (i < a.len) : (i += 1) {
        const ov1 = opWithOverflow(.sub, a[i], a_borrow);
        a_borrow = ov1[1];
        const ov2 = opWithOverflow(.add, ov1[0], r_carry);
        r[i] = ov2[0];
        r_carry = ov2[1];
    }

    // If both inputs don't share the same sign, an extra limb is required.
    if (a_positive != b_positive) {
        r[i] = r_carry;
    } else {
        assert(r_carry == 0);
    }

    assert(a_borrow == 0);
    assert(b_borrow == 0);

    return a_positive == b_positive;
}

/// r MUST NOT alias x.
pub fn llsquareBasecase(r: []Limb, x: []const Limb) void {
    const x_norm = x;
    assert(r.len >= 2 * x_norm.len + 1);
    assert(!slicesOverlap(r, x));

    // Compute the square of a N-limb bigint with only (N^2 + N)/2
    // multiplications by exploiting the symmetry of the coefficients around the
    // diagonal:
    //
    //           a   b   c *
    //           a   b   c =
    // -------------------
    //          ca  cb  cc +
    //      ba  bb  bc     +
    //  aa  ab  ac
    //
    // Note that:
    //  - Each mixed-product term appears twice for each column,
    //  - Squares are always in the 2k (0 <= k < N) column

    for (x_norm, 0..) |v, i| {
        // Accumulate all the x[i]*x[j] (with x!=j) products
        const overflow = llmulLimb(.add, r[2 * i + 1 ..], x_norm[i + 1 ..], v);
        assert(!overflow);
    }

    // Each product appears twice, multiply by 2
    _ = llshl(r, r[0 .. 2 * x_norm.len], 1);

    for (x_norm, 0..) |v, i| {
        // Compute and add the squares
        const overflow = llmulLimb(.add, r[2 * i ..], x[i..][0..1], v);
        assert(!overflow);
    }
}

/// Knuth 4.6.3
pub fn llpow(r: []Limb, a: []const Limb, b: u32, tmp_limbs: []Limb) void {
    var tmp1: []Limb = undefined;
    var tmp2: []Limb = undefined;

    // Multiplication requires no aliasing between the operand and the result
    // variable, use the output limbs and another temporary set to overcome this
    // limitation.
    // The initial assignment makes the result end in `r` so an extra memory
    // copy is saved, each 1 flips the index twice so it's only the zeros that
    // matter.
    const b_leading_zeros = @clz(b);
    const exp_zeros = @popCount(~b) - b_leading_zeros;
    if (exp_zeros & 1 != 0) {
        tmp1 = tmp_limbs;
        tmp2 = r;
    } else {
        tmp1 = r;
        tmp2 = tmp_limbs;
    }

    @memcpy(tmp1[0..a.len], a);
    @memset(tmp1[a.len..], 0);

    // Scan the exponent as a binary number, from left to right, dropping the
    // most significant bit set.
    // Square the result if the current bit is zero, square and multiply by a if
    // it is one.
    const exp_bits = 32 - 1 - b_leading_zeros;
    var exp = b << @as(u5, @intCast(1 + b_leading_zeros));

    var i: usize = 0;
    while (i < exp_bits) : (i += 1) {
        // Square
        @memset(tmp2, 0);
        llsquareBasecase(tmp2, tmp1[0..llnormalize(tmp1)]);
        mem.swap([]Limb, &tmp1, &tmp2);
        // Multiply by a
        const ov = @shlWithOverflow(exp, 1);
        exp = ov[0];
        if (ov[1] != 0) {
            @memset(tmp2, 0);
            llmulacc(.add, null, tmp2, tmp1[0..llnormalize(tmp1)], a);
            mem.swap([]Limb, &tmp1, &tmp2);
        }
    }
}

test "llshl shift by whole number of limb" {
    const padding = maxInt(Limb);

    var r: [10]Limb = @splat(padding);

    const A: Limb = @truncate(0xCCCCCCCCCCCCCCCCCCCCCCC);
    const B: Limb = @truncate(0x22222222222222222222222);

    const data = [2]Limb{ A, B };
    for (0..9) |i| {
        @memset(&r, padding);
        const len = llshl(&r, &data, i * @bitSizeOf(Limb));

        try std.testing.expectEqual(i + 2, len);
        try std.testing.expectEqualSlices(Limb, &data, r[i .. i + 2]);
        for (r[0..i]) |x|
            try std.testing.expectEqual(0, x);
        for (r[i + 2 ..]) |x|
            try std.testing.expectEqual(padding, x);
    }
}

test llshl {
    if (limb_bits != 64) return error.SkipZigTest;

    // 1 << 63
    const left_one = 0x8000000000000000;
    const maxint: Limb = 0xFFFFFFFFFFFFFFFF;

    // zig fmt: off
    try testOneShiftCase(.llshl, .{0,  &.{0},                               &.{0}});
    try testOneShiftCase(.llshl, .{0,  &.{1},                               &.{1}});
    try testOneShiftCase(.llshl, .{0,  &.{125484842448},                    &.{125484842448}});
    try testOneShiftCase(.llshl, .{0,  &.{0xdeadbeef},                      &.{0xdeadbeef}});
    try testOneShiftCase(.llshl, .{0,  &.{maxint},                          &.{maxint}});
    try testOneShiftCase(.llshl, .{0,  &.{left_one},                        &.{left_one}});
    try testOneShiftCase(.llshl, .{0,  &.{0, 1},                            &.{0, 1}});
    try testOneShiftCase(.llshl, .{0,  &.{1, 2},                            &.{1, 2}});
    try testOneShiftCase(.llshl, .{0,  &.{left_one, 1},                     &.{left_one, 1}});
    try testOneShiftCase(.llshl, .{1,  &.{0},                               &.{0}});
    try testOneShiftCase(.llshl, .{1,  &.{2},                               &.{1}});
    try testOneShiftCase(.llshl, .{1,  &.{250969684896},                    &.{125484842448}});
    try testOneShiftCase(.llshl, .{1,  &.{0x1bd5b7dde},                     &.{0xdeadbeef}});
    try testOneShiftCase(.llshl, .{1,  &.{0xfffffffffffffffe, 1},           &.{maxint}});
    try testOneShiftCase(.llshl, .{1,  &.{0, 1},                            &.{left_one}});
    try testOneShiftCase(.llshl, .{1,  &.{0, 2},                            &.{0, 1}});
    try testOneShiftCase(.llshl, .{1,  &.{2, 4},                            &.{1, 2}});
    try testOneShiftCase(.llshl, .{1,  &.{0, 3},                            &.{left_one, 1}});
    try testOneShiftCase(.llshl, .{5,  &.{32},                              &.{1}});
    try testOneShiftCase(.llshl, .{5,  &.{4015514958336},                   &.{125484842448}});
    try testOneShiftCase(.llshl, .{5,  &.{0x1bd5b7dde0},                    &.{0xdeadbeef}});
    try testOneShiftCase(.llshl, .{5,  &.{0xffffffffffffffe0, 0x1f},        &.{maxint}});
    try testOneShiftCase(.llshl, .{5,  &.{0, 16},                           &.{left_one}});
    try testOneShiftCase(.llshl, .{5,  &.{0, 32},                           &.{0, 1}});
    try testOneShiftCase(.llshl, .{5,  &.{32, 64},                          &.{1, 2}});
    try testOneShiftCase(.llshl, .{5,  &.{0, 48},                           &.{left_one, 1}});
    try testOneShiftCase(.llshl, .{64, &.{0, 1},                            &.{1}});
    try testOneShiftCase(.llshl, .{64, &.{0, 125484842448},                 &.{125484842448}});
    try testOneShiftCase(.llshl, .{64, &.{0, 0xdeadbeef},                   &.{0xdeadbeef}});
    try testOneShiftCase(.llshl, .{64, &.{0, maxint},                       &.{maxint}});
    try testOneShiftCase(.llshl, .{64, &.{0, left_one},                     &.{left_one}});
    try testOneShiftCase(.llshl, .{64, &.{0, 0, 1},                         &.{0, 1}});
    try testOneShiftCase(.llshl, .{64, &.{0, 1, 2},                         &.{1, 2}});
    try testOneShiftCase(.llshl, .{64, &.{0, left_one, 1},                  &.{left_one, 1}});
    try testOneShiftCase(.llshl, .{35, &.{0x800000000},                     &.{1}});
    try testOneShiftCase(.llshl, .{35, &.{13534986488655118336, 233},       &.{125484842448}});
    try testOneShiftCase(.llshl, .{35, &.{0xf56df77800000000, 6},           &.{0xdeadbeef}});
    try testOneShiftCase(.llshl, .{35, &.{0xfffffff800000000, 0x7ffffffff}, &.{maxint}});
    try testOneShiftCase(.llshl, .{35, &.{0, 17179869184},                  &.{left_one}});
    try testOneShiftCase(.llshl, .{35, &.{0, 0x800000000},                  &.{0, 1}});
    try testOneShiftCase(.llshl, .{35, &.{0x800000000, 0x1000000000},       &.{1, 2}});
    try testOneShiftCase(.llshl, .{35, &.{0, 0xc00000000},                  &.{left_one, 1}});
    try testOneShiftCase(.llshl, .{70, &.{0, 64},                           &.{1}});
    try testOneShiftCase(.llshl, .{70, &.{0, 8031029916672},                &.{125484842448}});
    try testOneShiftCase(.llshl, .{70, &.{0, 0x37ab6fbbc0},                 &.{0xdeadbeef}});
    try testOneShiftCase(.llshl, .{70, &.{0, 0xffffffffffffffc0, 63},       &.{maxint}});
    try testOneShiftCase(.llshl, .{70, &.{0, 0, 32},                        &.{left_one}});
    try testOneShiftCase(.llshl, .{70, &.{0, 0, 64},                        &.{0, 1}});
    try testOneShiftCase(.llshl, .{70, &.{0, 64, 128},                      &.{1, 2}});
    try testOneShiftCase(.llshl, .{70, &.{0, 0, 0x60},                      &.{left_one, 1}});
    // zig fmt: on
}

test "llshl shift 0" {
    const n = @bitSizeOf(Limb);
    if (n <= 20) return error.SkipZigTest;

    // zig fmt: off
    try testOneShiftCase(.llshl, .{0,   &.{0},    &.{0}});
    try testOneShiftCase(.llshl, .{1,   &.{0},    &.{0}});
    try testOneShiftCase(.llshl, .{5,   &.{0},    &.{0}});
    try testOneShiftCase(.llshl, .{13,  &.{0},    &.{0}});
    try testOneShiftCase(.llshl, .{20,  &.{0},    &.{0}});
    try testOneShiftCase(.llshl, .{0,   &.{0, 0}, &.{0, 0}});
    try testOneShiftCase(.llshl, .{2,   &.{0, 0}, &.{0, 0}});
    try testOneShiftCase(.llshl, .{7,   &.{0, 0}, &.{0, 0}});
    try testOneShiftCase(.llshl, .{11,  &.{0, 0}, &.{0, 0}});
    try testOneShiftCase(.llshl, .{19,  &.{0, 0}, &.{0, 0}});

    try testOneShiftCase(.llshl, .{0,   &.{0},                &.{0}});
    try testOneShiftCase(.llshl, .{n,   &.{0, 0},             &.{0}});
    try testOneShiftCase(.llshl, .{2*n, &.{0, 0, 0},          &.{0}});
    try testOneShiftCase(.llshl, .{3*n, &.{0, 0, 0, 0},       &.{0}});
    try testOneShiftCase(.llshl, .{4*n, &.{0, 0, 0, 0, 0},    &.{0}});
    try testOneShiftCase(.llshl, .{0,   &.{0, 0},             &.{0, 0}});
    try testOneShiftCase(.llshl, .{n,   &.{0, 0, 0},          &.{0, 0}});
    try testOneShiftCase(.llshl, .{2*n, &.{0, 0, 0, 0},       &.{0, 0}});
    try testOneShiftCase(.llshl, .{3*n, &.{0, 0, 0, 0, 0},    &.{0, 0}});
    try testOneShiftCase(.llshl, .{4*n, &.{0, 0, 0, 0, 0, 0}, &.{0, 0}});
    // zig fmt: on
}

test "llshr shift 0" {
    const n = @bitSizeOf(Limb);

    // zig fmt: off
    try testOneShiftCase(.llshr, .{0,   &.{0},    &.{0}});
    try testOneShiftCase(.llshr, .{1,   &.{0},    &.{0}});
    try testOneShiftCase(.llshr, .{5,   &.{0},    &.{0}});
    try testOneShiftCase(.llshr, .{13,  &.{0},    &.{0}});
    try testOneShiftCase(.llshr, .{20,  &.{0},    &.{0}});
    try testOneShiftCase(.llshr, .{0,   &.{0, 0}, &.{0, 0}});
    try testOneShiftCase(.llshr, .{2,   &.{0},    &.{0, 0}});
    try testOneShiftCase(.llshr, .{7,   &.{0},    &.{0, 0}});
    try testOneShiftCase(.llshr, .{11,  &.{0},    &.{0, 0}});
    try testOneShiftCase(.llshr, .{19,  &.{0},    &.{0, 0}});

    try testOneShiftCase(.llshr, .{n,   &.{0}, &.{0}});
    try testOneShiftCase(.llshr, .{2*n, &.{0}, &.{0}});
    try testOneShiftCase(.llshr, .{3*n, &.{0}, &.{0}});
    try testOneShiftCase(.llshr, .{4*n, &.{0}, &.{0}});
    try testOneShiftCase(.llshr, .{n,   &.{0}, &.{0, 0}});
    try testOneShiftCase(.llshr, .{2*n, &.{0}, &.{0, 0}});
    try testOneShiftCase(.llshr, .{3*n, &.{0}, &.{0, 0}});
    try testOneShiftCase(.llshr, .{4*n, &.{0}, &.{0, 0}});

    try testOneShiftCase(.llshr, .{1,  &.{}, &.{}});
    try testOneShiftCase(.llshr, .{2,  &.{}, &.{}});
    try testOneShiftCase(.llshr, .{64, &.{}, &.{}});
    // zig fmt: on
}

test "llshr to 0" {
    const n = @bitSizeOf(Limb);
    if (n != 64 and n != 32) return error.SkipZigTest;

    // zig fmt: off
    try testOneShiftCase(.llshr, .{1,   &.{0}, &.{0}});
    try testOneShiftCase(.llshr, .{1,   &.{0}, &.{1}});
    try testOneShiftCase(.llshr, .{5,   &.{0}, &.{1}});
    try testOneShiftCase(.llshr, .{65,  &.{0}, &.{0, 1}});
    try testOneShiftCase(.llshr, .{193, &.{0}, &.{0, 0, maxInt(Limb)}});
    try testOneShiftCase(.llshr, .{193, &.{0}, &.{maxInt(Limb), 1, maxInt(Limb)}});
    try testOneShiftCase(.llshr, .{193, &.{0}, &.{0xdeadbeef, 0xabcdefab, 0x1234}});
    // zig fmt: on
}

test "llshr single" {
    if (limb_bits != 64) return error.SkipZigTest;

    // 1 << 63
    const left_one = 0x8000000000000000;
    const maxint: Limb = 0xFFFFFFFFFFFFFFFF;

    // zig fmt: off
    try testOneShiftCase(.llshr, .{0,  &.{0},                  &.{0}});
    try testOneShiftCase(.llshr, .{0,  &.{1},                  &.{1}});
    try testOneShiftCase(.llshr, .{0,  &.{125484842448},       &.{125484842448}});
    try testOneShiftCase(.llshr, .{0,  &.{0xdeadbeef},         &.{0xdeadbeef}});
    try testOneShiftCase(.llshr, .{0,  &.{maxint},             &.{maxint}});
    try testOneShiftCase(.llshr, .{0,  &.{left_one},           &.{left_one}});
    try testOneShiftCase(.llshr, .{1,  &.{0},                  &.{0}});
    try testOneShiftCase(.llshr, .{1,  &.{1},                  &.{2}});
    try testOneShiftCase(.llshr, .{1,  &.{62742421224},        &.{125484842448}});
    try testOneShiftCase(.llshr, .{1,  &.{62742421223},        &.{125484842447}});
    try testOneShiftCase(.llshr, .{1,  &.{0x6f56df77},         &.{0xdeadbeef}});
    try testOneShiftCase(.llshr, .{1,  &.{0x7fffffffffffffff}, &.{maxint}});
    try testOneShiftCase(.llshr, .{1,  &.{0x4000000000000000}, &.{left_one}});
    try testOneShiftCase(.llshr, .{8,  &.{1},                  &.{256}});
    try testOneShiftCase(.llshr, .{8,  &.{490175165},          &.{125484842448}});
    try testOneShiftCase(.llshr, .{8,  &.{0xdeadbe},           &.{0xdeadbeef}});
    try testOneShiftCase(.llshr, .{8,  &.{0xffffffffffffff},   &.{maxint}});
    try testOneShiftCase(.llshr, .{8,  &.{0x80000000000000},   &.{left_one}});
    // zig fmt: on
}

test llshr {
    if (limb_bits != 64) return error.SkipZigTest;

    // 1 << 63
    const left_one = 0x8000000000000000;
    const maxint: Limb = 0xFFFFFFFFFFFFFFFF;

    // zig fmt: off
    try testOneShiftCase(.llshr, .{0,  &.{0, 0},                           &.{0, 0}});
    try testOneShiftCase(.llshr, .{0,  &.{0, 1},                           &.{0, 1}});
    try testOneShiftCase(.llshr, .{0,  &.{15, 1},                          &.{15, 1}});
    try testOneShiftCase(.llshr, .{0,  &.{987656565, 123456789456},        &.{987656565, 123456789456}});
    try testOneShiftCase(.llshr, .{0,  &.{0xfeebdaed, 0xdeadbeef},         &.{0xfeebdaed, 0xdeadbeef}});
    try testOneShiftCase(.llshr, .{0,  &.{1, maxint},                      &.{1, maxint}});
    try testOneShiftCase(.llshr, .{0,  &.{0, left_one},                    &.{0, left_one}});
    try testOneShiftCase(.llshr, .{1,  &.{0},                              &.{0, 0}});
    try testOneShiftCase(.llshr, .{1,  &.{left_one},                       &.{0, 1}});
    try testOneShiftCase(.llshr, .{1,  &.{0x8000000000000007},             &.{15, 1}});
    try testOneShiftCase(.llshr, .{1,  &.{493828282, 61728394728},         &.{987656565, 123456789456}});
    try testOneShiftCase(.llshr, .{1,  &.{0x800000007f75ed76, 0x6f56df77}, &.{0xfeebdaed, 0xdeadbeef}});
    try testOneShiftCase(.llshr, .{1,  &.{left_one, 0x7fffffffffffffff},   &.{1, maxint}});
    try testOneShiftCase(.llshr, .{1,  &.{0, 0x4000000000000000},          &.{0, left_one}});
    try testOneShiftCase(.llshr, .{64, &.{0},                              &.{0, 0}});
    try testOneShiftCase(.llshr, .{64, &.{1},                              &.{0, 1}});
    try testOneShiftCase(.llshr, .{64, &.{1},                              &.{15, 1}});
    try testOneShiftCase(.llshr, .{64, &.{123456789456},                   &.{987656565, 123456789456}});
    try testOneShiftCase(.llshr, .{64, &.{0xdeadbeef},                     &.{0xfeebdaed, 0xdeadbeef}});
    try testOneShiftCase(.llshr, .{64, &.{maxint},                         &.{1, maxint}});
    try testOneShiftCase(.llshr, .{64, &.{left_one},                       &.{0, left_one}});
    try testOneShiftCase(.llshr, .{72, &.{0},                              &.{0, 0}});
    try testOneShiftCase(.llshr, .{72, &.{0},                              &.{0, 1}});
    try testOneShiftCase(.llshr, .{72, &.{0},                              &.{15, 1}});
    try testOneShiftCase(.llshr, .{72, &.{482253083},                      &.{987656565, 123456789456}});
    try testOneShiftCase(.llshr, .{72, &.{0xdeadbe},                       &.{0xfeebdaed, 0xdeadbeef}});
    try testOneShiftCase(.llshr, .{72, &.{0xffffffffffffff},               &.{1, maxint}});
    try testOneShiftCase(.llshr, .{72, &.{0x80000000000000},               &.{0, left_one}});
    // zig fmt: on
}

const Case = struct { usize, []const Limb, []const Limb };

fn testOneShiftCase(comptime function: enum { llshr, llshl }, case: Case) !void {
    const func = if (function == .llshl) llshl else llshr;
    const shift_direction = if (function == .llshl) -1 else 1;

    try testOneShiftCaseNoAliasing(func, case);
    try testOneShiftCaseAliasing(func, case, shift_direction);
}

fn testOneShiftCaseNoAliasing(func: fn ([]Limb, []const Limb, usize) usize, case: Case) !void {
    const padding = maxInt(Limb);
    var r: [20]Limb = @splat(padding);

    const shift = case[0];
    const expected = case[1];
    const data = case[2];

    std.debug.assert(expected.len <= 20);

    const len = func(&r, data, shift);

    try std.testing.expectEqual(expected.len, len);
    try std.testing.expectEqualSlices(Limb, expected, r[0..len]);
    try std.testing.expect(mem.allEqual(Limb, r[len..], padding));
}

fn testOneShiftCaseAliasing(func: fn ([]Limb, []const Limb, usize) usize, case: Case, shift_direction: isize) !void {
    const padding = maxInt(Limb);
    var r: [60]Limb = @splat(padding);
    const base = 20;

    assert(shift_direction == 1 or shift_direction == -1);

    for (0..10) |limb_shift| {
        const shift = case[0];
        const expected = case[1];
        const data = case[2];

        std.debug.assert(expected.len <= 20);

        @memset(&r, padding);
        const final_limb_base: usize = @intCast(base + shift_direction * @as(isize, @intCast(limb_shift)));
        const written_data = r[final_limb_base..][0..data.len];
        @memcpy(written_data, data);

        const len = func(r[base..], written_data, shift);

        try std.testing.expectEqual(expected.len, len);
        try std.testing.expectEqualSlices(Limb, expected, r[base .. base + len]);
    }
}
