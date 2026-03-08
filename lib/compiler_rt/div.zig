const std = @import("std");
const compiler_rt = @import("../compiler_rt.zig");
const wideMultiply = compiler_rt.wideMultiply;

pub fn div32(dividend: f32, divisor: f32) f32 {
    return innerDiv(f32, dividend, divisor);
}

pub fn div64(dividend: f64, divisor: f64) f64 {
    return innerDiv(f64, dividend, divisor);
}

pub fn div128(dividend: f128, divisor: f128) f128 {
    return innerDiv(f128, dividend, divisor);
}

fn innerDiv(comptime FloatType: type, dividend: FloatType, divisor: FloatType) FloatType {
    const bitWidth = @bitSizeOf(FloatType);
    const twiceBitWidth: comptime_int = bitWidth * 2;
    const halfWidthBitCount: comptime_int = bitWidth / 2;

    const UInt = std.meta.Int(.unsigned, bitWidth);
    const DoubleUInt = std.meta.Int(.unsigned, twiceBitWidth);
    const HalfUInt = std.meta.Int(.unsigned, halfWidthBitCount);
    const UIntShift = std.math.Log2Int(UInt);
    const DoubleUIntShift = std.math.Log2Int(DoubleUInt);
    const HalfUIntShift = std.math.Log2Int(HalfUInt);

    const significandBitCount: comptime_int = std.math.floatMantissaBits(FloatType);
    const exponentBitCount: comptime_int = std.math.floatExponentBits(FloatType);

    const signBitMask: UInt = @as(UInt, 1) << (significandBitCount + exponentBitCount);
    const maximumExponent: u32 = (@as(u32, 1) << exponentBitCount) - 1;
    const exponentBias: i32 = @intCast(maximumExponent >> 1);
    const implicitSignificandBit: UInt = @as(UInt, 1) << significandBitCount;
    const quietNaNBit: UInt = implicitSignificandBit >> 1;
    const significandMask: UInt = implicitSignificandBit - 1;
    const absoluteValueMask: UInt = signBitMask - 1;
    const exponentMask: UInt = absoluteValueMask ^ significandMask;
    const quietNaNRepresentation: UInt = exponentMask | quietNaNBit;
    const infinityRepresentation: UInt = @bitCast(std.math.inf(FloatType));
    const implicitSignificandBitLeadingZeroCount = @clz(implicitSignificandBit);
    const specialCaseExponentThreshold: u32 = maximumExponent - 1;

    const halfIterations: u32 = switch (bitWidth) {
        32 => 0,
        64 => 3,
        128 => 4,
        else => @compileError("Unsupported float bit width for halfIterations"),
    };
    const hasHalfIterations = halfIterations > 0;
    const divisorUQ1LeftShift: UIntShift = if (bitWidth > (significandBitCount + 1))
        @intCast(bitWidth - (significandBitCount + 1))
    else
        0;
    const toUQ1HalfShift: UIntShift = if (hasHalfIterations)
        @intCast(halfWidthBitCount)
    else
        0;
    const toUQ0HalfShift: UIntShift = if (hasHalfIterations)
        @intCast(halfWidthBitCount - 1)
    else
        0;
    const fullIterations: u32 = switch (bitWidth) {
        32 => 3,
        else => 0,
    };
    const hasNativeFullIterations = fullIterations > 0;
    const toUQ1FullShift: DoubleUIntShift = @intCast(bitWidth);
    const toUQ0FullShift: DoubleUIntShift = @intCast(bitWidth - 1);
    const halfWidthLowMask: UInt = if (hasHalfIterations)
        (1 << toUQ1HalfShift) - 1
    else
        0;
    const dividendRepresentation: UInt = @bitCast(dividend);
    const dividendAbsoluteValue: UInt = dividendRepresentation & absoluteValueMask;
    const dividendExponent: u32 = @truncate((dividendRepresentation >> significandBitCount) & maximumExponent);
    var dividendSignificand: UInt = dividendRepresentation & significandMask;

    const divisorRepresentation: UInt = @bitCast(divisor);
    const divisorAbsoluteValue: UInt = divisorRepresentation & absoluteValueMask;
    const divisorExponent: u32 = @truncate((divisorRepresentation >> significandBitCount) & maximumExponent);
    var divisorSignificand: UInt = divisorRepresentation & significandMask;

    const quotientSignBit: UInt = (dividendRepresentation ^ divisorRepresentation) & signBitMask;
    const exponentDifference: i32 = @bitCast(dividendExponent -% divisorExponent);

    var writtenExponent: i32 = exponentDifference +% exponentBias;

    if (dividendExponent -% 1 >= specialCaseExponentThreshold or divisorExponent -% 1 >= specialCaseExponentThreshold) {
        if (dividendAbsoluteValue > infinityRepresentation) return @bitCast(dividendRepresentation | quietNaNBit);
        if (divisorAbsoluteValue > infinityRepresentation) return @bitCast(divisorRepresentation | quietNaNBit);
        if (dividendAbsoluteValue == infinityRepresentation) {
            if (divisorAbsoluteValue == infinityRepresentation) return @bitCast(quietNaNRepresentation);
            return @bitCast(dividendAbsoluteValue | quotientSignBit);
        }
        if (divisorAbsoluteValue == infinityRepresentation) return @bitCast(quotientSignBit);
        if (dividendAbsoluteValue == 0) {
            if (divisorAbsoluteValue == 0) return @bitCast(quietNaNRepresentation);
            return @bitCast(quotientSignBit);
        }
        if (divisorAbsoluteValue == 0) return @bitCast(infinityRepresentation | quotientSignBit);
        if (dividendAbsoluteValue < implicitSignificandBit) {
            const dividendShift = @clz(dividendSignificand) - implicitSignificandBitLeadingZeroCount;
            dividendSignificand <<= @intCast(dividendShift);
            writtenExponent +%= 1 - dividendShift;
        }
        if (divisorAbsoluteValue < implicitSignificandBit) {
            const divisorShift = @clz(divisorSignificand) - implicitSignificandBitLeadingZeroCount;
            divisorSignificand <<= @intCast(divisorShift);
            writtenExponent -%= 1 - divisorShift;
        }
    }

    dividendSignificand |= implicitSignificandBit;
    divisorSignificand |= implicitSignificandBit;

    const divisorUQ1: UInt = divisorSignificand << divisorUQ1LeftShift;
    var reciprocalUQ0: UInt = undefined;
    var divisorUQ1HalfWidth: HalfUInt = 0;
    var reciprocalHalfWidthUQ0: HalfUInt = 0;

    if (comptime hasHalfIterations) {
        const divisorUQ1HalfWidthShift: comptime_int = significandBitCount + 1 - halfWidthBitCount;

        const reciprocalSeedBaseFor32BitHalfWidth: HalfUInt = 0x7504_f333;
        const reciprocalSeedLeftShift: HalfUIntShift = @intCast(halfWidthBitCount - 32);
        const reciprocalSeedUQ0HalfWidth: HalfUInt = reciprocalSeedBaseFor32BitHalfWidth << reciprocalSeedLeftShift;

        divisorUQ1HalfWidth = @truncate(
            divisorSignificand >> divisorUQ1HalfWidthShift,
        );
        reciprocalHalfWidthUQ0 = reciprocalSeedUQ0HalfWidth -% divisorUQ1HalfWidth;

        inline for (0..halfIterations) |_| {
            const correctionUQ1HalfWidth: HalfUInt = 0 -%
                @as(HalfUInt, @truncate(
                    (@as(UInt, reciprocalHalfWidthUQ0) * divisorUQ1HalfWidth) >> toUQ1HalfShift,
                ));

            reciprocalHalfWidthUQ0 = @as(HalfUInt, @truncate(
                (@as(UInt, reciprocalHalfWidthUQ0) * correctionUQ1HalfWidth) >> toUQ0HalfShift,
            ));
        }

        reciprocalHalfWidthUQ0 -%= 1;
        reciprocalUQ0 = (@as(UInt, reciprocalHalfWidthUQ0) << toUQ1HalfShift) -% 1;
    } else {
        const reciprocalSeedBaseFor32BitFullWidth: UInt = 0x7504_f333;
        const reciprocalSeedLeftShiftFullWidth: UIntShift = if (bitWidth > 32)
            @intCast(bitWidth - 32)
        else
            0;
        const reciprocalSeedUQ0FullWidth: UInt = reciprocalSeedBaseFor32BitFullWidth << reciprocalSeedLeftShiftFullWidth;
        reciprocalUQ0 = reciprocalSeedUQ0FullWidth -% divisorUQ1;
    }

    if (comptime hasNativeFullIterations) {
        inline for (0..fullIterations) |_| {
            const correctionUQ1: UInt = 0 -% @as(UInt, @truncate(
                (@as(DoubleUInt, reciprocalUQ0) * divisorUQ1) >> toUQ1FullShift,
            ));

            reciprocalUQ0 = @as(UInt, @truncate(
                (@as(DoubleUInt, reciprocalUQ0) * correctionUQ1) >> toUQ0FullShift,
            ));
        }
    } else {
        const divisorLowHalf: UInt = divisorUQ1 & halfWidthLowMask;

        const correctionUQ1: UInt = 0 -% (@as(UInt, reciprocalHalfWidthUQ0) * divisorUQ1HalfWidth +%
            ((@as(UInt, reciprocalHalfWidthUQ0) * divisorLowHalf) >> toUQ1HalfShift) -%
            1);

        const correctionLowHalf: UInt = correctionUQ1 & halfWidthLowMask;
        const correctionHighHalf: UInt = correctionUQ1 >> toUQ1HalfShift;

        reciprocalUQ0 =
            ((@as(UInt, reciprocalHalfWidthUQ0) * correctionHighHalf) << 1) +%
            ((@as(UInt, reciprocalHalfWidthUQ0) * correctionLowHalf) >> toUQ0HalfShift) -%
            2;

        reciprocalUQ0 -%= 1;
    }

    reciprocalUQ0 -%= 2;

    const reciprocalPrecision: UInt = switch (bitWidth) {
        32 => 10,
        64 => 220,
        128 => 13922,
        else => @compileError("Unsupported float bit width for reciprocal precision"),
    };
    reciprocalUQ0 -%= reciprocalPrecision;

    var quotientUQ1: UInt = undefined;
    var discardedProductLow: UInt = undefined;
    wideMultiply(UInt, reciprocalUQ0, dividendSignificand << 1, &quotientUQ1, &discardedProductLow);

    var residualLo: UInt = undefined;
    if (quotientUQ1 < (implicitSignificandBit << 1)) {
        if (quotientUQ1 < implicitSignificandBit) {
            quotientUQ1 <<= 1;
            writtenExponent -%= 1;
        }

        residualLo = (dividendSignificand << (significandBitCount + 1)) -% quotientUQ1 *% divisorSignificand;
        writtenExponent -%= 1;
        dividendSignificand <<= 1;
    } else {
        quotientUQ1 >>= 1;
        residualLo = (dividendSignificand << significandBitCount) -% quotientUQ1 *% divisorSignificand;
    }

    if (writtenExponent >= @as(i32, @intCast(maximumExponent))) {
        return @bitCast(infinityRepresentation | quotientSignBit);
    }

    var absResult: UInt = undefined;
    if (writtenExponent > 0) {
        absResult = quotientUQ1 & significandMask;
        absResult |= @as(UInt, @intCast(writtenExponent)) << significandBitCount;
        residualLo <<= 1;
    } else {
        const denormalShiftSigned = significandBitCount + writtenExponent;
        if (denormalShiftSigned < 0) {
            return @bitCast(quotientSignBit);
        }

        absResult = quotientUQ1 >> @as(UIntShift, @intCast(-writtenExponent + 1));
        residualLo =
            (dividendSignificand << @as(UIntShift, @intCast(denormalShiftSigned))) -%
            ((absResult *% divisorSignificand) << 1);
    }

    residualLo +%= absResult & 1;
    absResult +%= @intFromBool(residualLo > divisorSignificand);

    const additionalRoundingSteps: u32 = switch (bitWidth) {
        128 => 2,
        else => 0,
    };
    inline for (0..additionalRoundingSteps) |roundingStep| {
        absResult +%= @intFromBool(
            absResult < infinityRepresentation and
                residualLo > 2 * roundingStep + 3 *% divisorSignificand,
        );
    }

    return @bitCast(absResult | quotientSignBit);
}

fn expectDiv32ToBits(dividend: f32, divisor: f32, expectedResult: u32) !void {
    const resultBits: u32 = @bitCast(div32(dividend, divisor));
    try std.testing.expectEqual(expectedResult, resultBits);
}

fn expectDiv64ToBits(dividend: f64, divisor: f64, expectedResult: u64) !void {
    const resultBits: u64 = @bitCast(div64(dividend, divisor));
    try std.testing.expectEqual(expectedResult, resultBits);
}

fn expectDiv128ToBits(dividend: f128, divisor: f128, expectedResult: u128) !void {
    const resultBits: u128 = @bitCast(div128(dividend, divisor));
    try std.testing.expectEqual(expectedResult, resultBits);
}

test "div32 special-case handling" {
    const quiet_nan_bit: u32 = 0x0040_0000;
    const quiet_nan_representation: u32 = 0x7fc0_0000;
    const sign_bit_mask: u32 = 0x8000_0000;
    const infinity_representation: u32 = 0x7f80_0000;

    const dividend_signaling_nan_bits: u32 = 0x7f80_0123;
    const divisor_signaling_nan_bits: u32 = 0x7f80_0456;

    try expectDiv32ToBits(@bitCast(dividend_signaling_nan_bits), 1.0, dividend_signaling_nan_bits | quiet_nan_bit);
    try expectDiv32ToBits(1.0, @bitCast(divisor_signaling_nan_bits), divisor_signaling_nan_bits | quiet_nan_bit);
    try expectDiv32ToBits(std.math.inf(f32), std.math.inf(f32), quiet_nan_representation);
    try expectDiv32ToBits(-std.math.inf(f32), 2.0, infinity_representation | sign_bit_mask);
    try expectDiv32ToBits(-3.0, std.math.inf(f32), sign_bit_mask);
    try expectDiv32ToBits(0.0, 0.0, quiet_nan_representation);
    try expectDiv32ToBits(@bitCast(sign_bit_mask), 2.0, sign_bit_mask);
    try expectDiv32ToBits(-3.0, 0.0, infinity_representation | sign_bit_mask);
}

test "div64 special-case handling" {
    const quiet_nan_bit: u64 = 0x0008_0000_0000_0000;
    const quiet_nan_representation: u64 = 0x7ff8_0000_0000_0000;
    const sign_bit_mask: u64 = 0x8000_0000_0000_0000;
    const infinity_representation: u64 = 0x7ff0_0000_0000_0000;

    const dividend_signaling_nan_bits: u64 = 0x7ff0_0000_0000_0123;
    const divisor_signaling_nan_bits: u64 = 0x7ff0_0000_0000_0456;

    try expectDiv64ToBits(@bitCast(dividend_signaling_nan_bits), 1.0, dividend_signaling_nan_bits | quiet_nan_bit);
    try expectDiv64ToBits(1.0, @bitCast(divisor_signaling_nan_bits), divisor_signaling_nan_bits | quiet_nan_bit);
    try expectDiv64ToBits(std.math.inf(f64), std.math.inf(f64), quiet_nan_representation);
    try expectDiv64ToBits(-std.math.inf(f64), 2.0, infinity_representation | sign_bit_mask);
    try expectDiv64ToBits(-3.0, std.math.inf(f64), sign_bit_mask);
    try expectDiv64ToBits(0.0, 0.0, quiet_nan_representation);
    try expectDiv64ToBits(@bitCast(sign_bit_mask), 2.0, sign_bit_mask);
    try expectDiv64ToBits(-3.0, 0.0, infinity_representation | sign_bit_mask);
}

test "div128 special-case handling" {
    const quiet_nan_bit: u128 = 0x0000_8000_0000_0000_0000_0000_0000_0000;
    const quiet_nan_representation: u128 = 0x7fff_8000_0000_0000_0000_0000_0000_0000;
    const sign_bit_mask: u128 = 0x8000_0000_0000_0000_0000_0000_0000_0000;
    const infinity_representation: u128 = 0x7fff_0000_0000_0000_0000_0000_0000_0000;

    const dividend_signaling_nan_bits: u128 = 0x7fff_0000_0000_0000_0000_0000_0000_0123;
    const divisor_signaling_nan_bits: u128 = 0x7fff_0000_0000_0000_0000_0000_0000_0456;

    try expectDiv128ToBits(@bitCast(dividend_signaling_nan_bits), 1.0, dividend_signaling_nan_bits | quiet_nan_bit);
    try expectDiv128ToBits(1.0, @bitCast(divisor_signaling_nan_bits), divisor_signaling_nan_bits | quiet_nan_bit);
    try expectDiv128ToBits(std.math.inf(f128), std.math.inf(f128), quiet_nan_representation);
    try expectDiv128ToBits(-std.math.inf(f128), 2.0, infinity_representation | sign_bit_mask);
    try expectDiv128ToBits(-3.0, std.math.inf(f128), sign_bit_mask);
    try expectDiv128ToBits(0.0, 0.0, quiet_nan_representation);
    try expectDiv128ToBits(@bitCast(sign_bit_mask), 2.0, sign_bit_mask);
    try expectDiv128ToBits(-3.0, 0.0, infinity_representation | sign_bit_mask);
}

test "div32 rounding and denormal path" {
    try expectDiv32ToBits(1.0, 3.0, 0x3eaa_aaab);
    try expectDiv32ToBits(2.3509887e-38, 2.0, 0x0080_0000);
    try expectDiv32ToBits(1.0, 0x1.fffffep-1, 0x3f80_0001);
}

test "div64 rounding and denormal path" {
    try expectDiv64ToBits(1.0, 3.0, 0x3fd5_5555_5555_5555);
    try expectDiv64ToBits(4.450147717014403e-308, 2.0, 0x0010_0000_0000_0000);
    try expectDiv64ToBits(1.0, 0x1.fffffffffffffp-1, 0x3ff0_0000_0000_0001);
}

test "div128 rounding and denormal path" {
    try expectDiv128ToBits(6.72420628622418701252535563464350521E-4932, 2.0, 0x0001_0000_0000_0000_0000_0000_0000_0000);
    try expectDiv128ToBits(1.0, 0x1.ffffffffffffffffffffffffffffp-1, 0x3fff_0000_0000_0000_0000_0000_0000_0001);
}
