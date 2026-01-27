const std = @import("std");

// ----------------------------------------------------------------------------
// AVR OPTIMIZED MATH IMPLEMENTATIONS
// ----------------------------------------------------------------------------
// These implementations use 32-bit integer approximations to bypass the
// LLVM AVR backend's inability to handle complex 64-bit float emulation
// without crashing.

pub fn sqrtf(x: f32) f32 {
    const u = @as(u32, @bitCast(x));

    // Extract Components
    const sign = u & 0x80000000;
    var exp = (u >> 23) & 0xFF;
    var mant = u & 0x7FFFFF;

    // Edge Cases
    if (exp == 0xFF) return x; // NaN or Inf
    if (exp == 0) return x; // 0.0 or subnormal
    if (sign != 0) return 0.0; // Negative input -> 0.0

    // Add Hidden Bit (1.xxxx)
    mant |= 0x800000;

    // Exponent Math
    const bias = 127;
    var true_exp = @as(i16, @intCast(exp)) - bias;

    // Handle Odd Exponents
    // If exp is odd, reduce by 1 to make even, and shift mantissa left to compensate.
    if ((true_exp & 1) != 0) {
        mant <<= 1;
        true_exp -= 1;
    }

    // Halve the exponent
    true_exp >>= 1;
    exp = @as(u32, @intCast(true_exp + bias));

    // Alignment
    // Shift input mantissa left to align with Bit 30 for maximum precision
    // 0x800000 (Bit 23) << 7 = Bit 30
    var val: u32 = mant << 7;
    var res: u32 = 0;
    var bit: u32 = 1 << 30;

    // Integer Square Root Loop
    while (bit != 0) {
        if (val >= res + bit) {
            val -= res + bit;
            res = (res >> 1) + bit;
        } else {
            res >>= 1;
        }
        bit >>= 2;
    }

    // Re-Alignment
    // Shift result back to align with Bit 23 (Mantissa)
    if (res < (1 << 23)) {
        res <<= 8;
    }

    // Mask and Return
    res &= 0x7FFFFF;
    const result_u = (sign) | (exp << 23) | res;
    return @as(f32, @bitCast(result_u));
}
