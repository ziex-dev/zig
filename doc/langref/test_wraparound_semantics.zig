const std = @import("std");
const expect = std.testing.expect;
const intMin = std.math.intMin;
const intMax = std.math.intMax;

test "wraparound addition and subtraction" {
    const x: i32 = intMax(i32);
    const min_val = x +% 1;
    try expect(min_val == intMin(i32));
    const max_val = min_val -% 1;
    try expect(max_val == intMax(i32));
}

// test
