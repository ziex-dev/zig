const std = @import("std");
const builtin = @import("builtin");
const intMin = std.math.intMin;
const intMax = std.math.intMax;
const expect = std.testing.expect;

test "saturating add" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            try testSatAdd(i8, -3, 10, 7);
            try testSatAdd(i8, 3, -10, -7);
            try testSatAdd(i8, -128, -128, -128);
            try testSatAdd(i2, 1, 1, 1);
            try testSatAdd(i2, 1, -1, 0);
            try testSatAdd(i2, -1, -1, -2);
            try testSatAdd(i64, intMax(i64), 1, intMax(i64));
            try testSatAdd(i8, 127, 127, 127);
            try testSatAdd(u2, 0, 0, 0);
            try testSatAdd(u2, 0, 1, 1);
            try testSatAdd(u8, 3, 10, 13);
            try testSatAdd(u8, 255, 255, 255);
            try testSatAdd(u2, 3, 2, 3);
            try testSatAdd(u3, 7, 1, 7);
        }

        fn testSatAdd(comptime T: type, lhs: T, rhs: T, expected: T) !void {
            try expect((lhs +| rhs) == expected);

            var x = lhs;
            x +|= rhs;
            try expect(x == expected);
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();

    try comptime S.testSatAdd(comptime_int, 0, 0, 0);
    try comptime S.testSatAdd(comptime_int, -1, 1, 0);
    try comptime S.testSatAdd(comptime_int, 3, 2, 5);
    try comptime S.testSatAdd(comptime_int, -3, -2, -5);
    try comptime S.testSatAdd(comptime_int, 3, -2, 1);
    try comptime S.testSatAdd(comptime_int, -3, 2, -1);
    try comptime S.testSatAdd(comptime_int, 651075816498665588400716961808225370057, 468229432685078038144554201546849378455, 1119305249183743626545271163355074748512);
    try comptime S.testSatAdd(comptime_int, 7, -593423721213448152027139550640105366508, -593423721213448152027139550640105366501);
}

test "saturating add 128bit" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            try testSatAdd(i128, intMax(i128), -intMax(i128), 0);
            try testSatAdd(i128, intMin(i128), intMax(i128), -1);
            try testSatAdd(u128, intMax(u128), 1, intMax(u128));
        }
        fn testSatAdd(comptime T: type, lhs: T, rhs: T, expected: T) !void {
            try expect((lhs +| rhs) == expected);

            var x = lhs;
            x +|= rhs;
            try expect(x == expected);
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();
}

test "saturating subtraction" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            try testSatSub(i8, -3, 10, -13);
            try testSatSub(i8, -3, -10, 7);
            try testSatSub(i8, -128, -128, 0);
            try testSatSub(i8, -1, 127, -128);
            try testSatSub(i2, 1, 1, 0);
            try testSatSub(i2, 1, -1, 1);
            try testSatSub(i2, -2, -2, 0);
            try testSatSub(i64, intMin(i64), 1, intMin(i64));
            try testSatSub(u2, 0, 0, 0);
            try testSatSub(u2, 0, 1, 0);
            try testSatSub(u5, 0, 31, 0);
            try testSatSub(u8, 10, 3, 7);
            try testSatSub(u8, 0, 255, 0);
        }

        fn testSatSub(comptime T: type, lhs: T, rhs: T, expected: T) !void {
            try expect((lhs -| rhs) == expected);

            var x = lhs;
            x -|= rhs;
            try expect(x == expected);
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();

    try comptime S.testSatSub(comptime_int, 0, 0, 0);
    try comptime S.testSatSub(comptime_int, 1, 1, 0);
    try comptime S.testSatSub(comptime_int, 3, 2, 1);
    try comptime S.testSatSub(comptime_int, -3, -2, -1);
    try comptime S.testSatSub(comptime_int, 3, -2, 5);
    try comptime S.testSatSub(comptime_int, -3, 2, -5);
    try comptime S.testSatSub(comptime_int, 651075816498665588400716961808225370057, 468229432685078038144554201546849378455, 182846383813587550256162760261375991602);
    try comptime S.testSatSub(comptime_int, 7, -593423721213448152027139550640105366508, 593423721213448152027139550640105366515);
}

test "saturating subtraction 128bit" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            try testSatSub(i128, intMax(i128), -1, intMax(i128));
            try testSatSub(i128, intMin(i128), -intMax(i128), -1);
            try testSatSub(u128, 0, intMax(u128), 0);
        }

        fn testSatSub(comptime T: type, lhs: T, rhs: T, expected: T) !void {
            try expect((lhs -| rhs) == expected);

            var x = lhs;
            x -|= rhs;
            try expect(x == expected);
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();
}

fn testSatMul(comptime T: type, a: T, b: T, expected: T) !void {
    const res: T = a *| b;
    try expect(res == expected);
}

test "saturating multiplication <= 32 bits" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isWasm()) {
        // https://github.com/ziglang/zig/issues/9660
        return error.SkipZigTest;
    }

    try testSatMul(u8, 0, intMax(u8), 0);
    try testSatMul(u8, 1 << 7, 1 << 7, intMax(u8));
    try testSatMul(u8, intMax(u8) - 1, 2, intMax(u8));
    try testSatMul(u8, 1 << 4, 1 << 4, intMax(u8));
    try testSatMul(u8, 1 << 4, 1 << 3, 1 << 7);
    try testSatMul(u8, 1 << 5, 1 << 3, intMax(u8));
    try testSatMul(u8, 10, 20, 200);

    try testSatMul(u16, 0, intMax(u16), 0);
    try testSatMul(u16, 1 << 15, 1 << 15, intMax(u16));
    try testSatMul(u16, intMax(u16) - 1, 2, intMax(u16));
    try testSatMul(u16, 1 << 8, 1 << 8, intMax(u16));
    try testSatMul(u16, 1 << 12, 1 << 3, 1 << 15);
    try testSatMul(u16, 1 << 13, 1 << 3, intMax(u16));
    try testSatMul(u16, 10, 20, 200);

    try testSatMul(u32, 0, intMax(u32), 0);
    try testSatMul(u32, 1 << 31, 1 << 31, intMax(u32));
    try testSatMul(u32, intMax(u32) - 1, 2, intMax(u32));
    try testSatMul(u32, 1 << 16, 1 << 16, intMax(u32));
    try testSatMul(u32, 1 << 28, 1 << 3, 1 << 31);
    try testSatMul(u32, 1 << 29, 1 << 3, intMax(u32));
    try testSatMul(u32, 10, 20, 200);

    try testSatMul(i8, 0, intMax(i8), 0);
    try testSatMul(i8, 0, intMin(i8), 0);
    try testSatMul(i8, 1 << 6, 1 << 6, intMax(i8));
    try testSatMul(i8, intMin(i8), intMin(i8), intMax(i8));
    try testSatMul(i8, intMax(i8) - 1, 2, intMax(i8));
    try testSatMul(i8, intMin(i8) + 1, 2, intMin(i8));
    try testSatMul(i8, 1 << 4, 1 << 4, intMax(i8));
    try testSatMul(i8, intMin(i4), 1 << 4, intMin(i8));
    try testSatMul(i8, 10, 12, 120);
    try testSatMul(i8, 10, -12, -120);

    try testSatMul(i16, 0, intMax(i16), 0);
    try testSatMul(i16, 0, intMin(i16), 0);
    try testSatMul(i16, 1 << 14, 1 << 14, intMax(i16));
    try testSatMul(i16, intMin(i16), intMin(i16), intMax(i16));
    try testSatMul(i16, intMax(i16) - 1, 2, intMax(i16));
    try testSatMul(i16, intMin(i16) + 1, 2, intMin(i16));
    try testSatMul(i16, 1 << 8, 1 << 8, intMax(i16));
    try testSatMul(i16, intMin(i8), 1 << 8, intMin(i16));
    try testSatMul(i16, 10, 12, 120);
    try testSatMul(i16, 10, -12, -120);

    try testSatMul(i32, 0, intMax(i32), 0);
    try testSatMul(i32, 0, intMin(i32), 0);
    try testSatMul(i32, 1 << 30, 1 << 30, intMax(i32));
    try testSatMul(i32, intMin(i32), intMin(i32), intMax(i32));
    try testSatMul(i32, intMax(i32) - 1, 2, intMax(i32));
    try testSatMul(i32, intMin(i32) + 1, 2, intMin(i32));
    try testSatMul(i32, 1 << 16, 1 << 16, intMax(i32));
    try testSatMul(i32, intMin(i16), 1 << 16, intMin(i32));
    try testSatMul(i32, 10, 12, 120);
    try testSatMul(i32, 10, -12, -120);
}

test "saturating mul i64, i128" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try testSatMul(i64, 0, intMax(i64), 0);
    try testSatMul(i64, 0, intMin(i64), 0);
    try testSatMul(i64, 1 << 62, 1 << 62, intMax(i64));
    try testSatMul(i64, intMin(i64), intMin(i64), intMax(i64));
    try testSatMul(i64, intMax(i64) - 1, 2, intMax(i64));
    try testSatMul(i64, intMin(i64) + 1, 2, intMin(i64));
    try testSatMul(i64, 1 << 32, 1 << 32, intMax(i64));
    try testSatMul(i64, intMin(i32), 1 << 32, intMin(i64));
    try testSatMul(i64, 10, 12, 120);
    try testSatMul(i64, 10, -12, -120);

    try testSatMul(i128, 0, intMax(i128), 0);
    try testSatMul(i128, 0, intMin(i128), 0);
    try testSatMul(i128, 1 << 126, 1 << 126, intMax(i128));
    try testSatMul(i128, intMin(i128), intMin(i128), intMax(i128));
    try testSatMul(i128, intMax(i128) - 1, 2, intMax(i128));
    try testSatMul(i128, intMin(i128) + 1, 2, intMin(i128));
    try testSatMul(i128, 1 << 64, 1 << 64, intMax(i128));
    try testSatMul(i128, intMin(i64), 1 << 64, intMin(i128));
    try testSatMul(i128, 10, 12, 120);
    try testSatMul(i128, 10, -12, -120);
}

test "saturating multiplication" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isWasm()) {
        // https://github.com/ziglang/zig/issues/9660
        return error.SkipZigTest;
    }

    const S = struct {
        fn doTheTest() !void {
            try testSatMul(i8, -3, 10, -30);
            try testSatMul(i4, 2, 4, 7);
            try testSatMul(i8, 2, 127, 127);
            try testSatMul(i8, -128, -128, 127);
            try testSatMul(i8, intMax(i8), intMax(i8), intMax(i8));
            try testSatMul(i16, intMax(i16), -1, intMin(i16) + 1);
            try testSatMul(i128, intMax(i128), -1, intMin(i128) + 1);
            try testSatMul(i128, intMin(i128), -1, intMax(i128));
            try testSatMul(u8, 10, 3, 30);
            try testSatMul(u8, 2, 255, 255);
            try testSatMul(u128, intMax(u128), intMax(u128), intMax(u128));
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();

    try comptime testSatMul(comptime_int, 0, 0, 0);
    try comptime testSatMul(comptime_int, 3, 2, 6);
    try comptime testSatMul(comptime_int, 651075816498665588400716961808225370057, 468229432685078038144554201546849378455, 304852860194144160265083087140337419215516305999637969803722975979232817921935);
    try comptime testSatMul(comptime_int, 7, -593423721213448152027139550640105366508, -4153966048494137064189976854480737565556);
}

test "saturating shift-left" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            try testSatShl(i8, 1, u8, 2, 4);
            try testSatShl(i8, 127, u8, 1, 127);
            try testSatShl(i8, -128, u8, 1, -128);
            // TODO: remove this check once #9668 is completed
            if (!builtin.cpu.arch.isWasm()) {
                // skip testing ints > 64 bits on wasm due to miscompilation / wasmtime ci error
                try testSatShl(i128, intMax(i128), u128, 64, intMax(i128));
                try testSatShl(u128, intMax(u128), u128, 64, intMax(u128));
            }
            try testSatShl(u8, 1, u8, 2, 4);
            try testSatShl(u8, 255, u8, 1, 255);
            try testSatShl(i8, -3, u4, 8, intMin(i8));
            try testSatShl(i8, 0, u4, 8, 0);
            try testSatShl(i8, 3, u4, 8, intMax(i8));
            try testSatShl(u8, 0, u4, 8, 0);
            try testSatShl(u8, 3, u4, 8, intMax(u8));
        }

        fn testSatShl(comptime Lhs: type, lhs: Lhs, comptime Rhs: type, rhs: Rhs, expected: Lhs) !void {
            try expect((lhs <<| rhs) == expected);

            var x = lhs;
            x <<|= rhs;
            try expect(x == expected);
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();

    try comptime S.testSatShl(comptime_int, 0, comptime_int, 0, 0);
    try comptime S.testSatShl(comptime_int, 1, comptime_int, 2, 4);
    try comptime S.testSatShl(comptime_int, 13, comptime_int, 150, 18554220005177478453757717602843436772975706112);
    try comptime S.testSatShl(comptime_int, -582769, comptime_int, 180, -893090893854873184096635538665358532628308979495815656505344);
}

test "saturating shift-left large rhs" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest;

    {
        var lhs: u8 = undefined;
        lhs = 1;
        const ct_rhs: u1024 = 1 << 1023;
        var rt_rhs: u1024 = undefined;
        rt_rhs = ct_rhs;
        try expect(lhs <<| ct_rhs == intMax(u8));
        try expect(lhs <<| rt_rhs == intMax(u8));
    }
}

test "saturating shl uses the LHS type" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const lhs_const: u8 = 1;
    var lhs_var: u8 = 1;
    _ = &lhs_var;

    const rhs_const: usize = 8;
    var rhs_var: usize = 8;
    _ = &rhs_var;

    try expect((lhs_const <<| 8) == 255);
    try expect((lhs_const <<| rhs_const) == 255);
    try expect((lhs_const <<| rhs_var) == 255);

    try expect((lhs_var <<| 8) == 255);
    try expect((lhs_var <<| rhs_const) == 255);
    try expect((lhs_var <<| rhs_var) == 255);

    try expect((@as(u8, 1) <<| 8) == 255);
    try expect((@as(u8, 1) <<| rhs_const) == 255);
    try expect((@as(u8, 1) <<| rhs_var) == 255);

    try expect((1 <<| @as(u8, 200)) == 1606938044258990275541962092341162602522202993782792835301376);
}
