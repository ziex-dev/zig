const cmp = @import("cmp.zig");
const testing = @import("std").testing;

fn test__cmpdi2(a: i64, b: i64, expected: i64) !void {
    const result = cmp.__cmpdi2(a, b);
    try testing.expectEqual(expected, result);
}

test "cmpdi2" {
    // intMin == -9223372036854775808
    // intMax == 9223372036854775807
    // intMin/2 == -4611686018427387904
    // intMax/2 == 4611686018427387903
    // 1. equality intMin, intMin+1, intMin/2, 0, intMax/2, intMax-1, intMax
    try test__cmpdi2(-9223372036854775808, -9223372036854775808, 1);
    try test__cmpdi2(-9223372036854775807, -9223372036854775807, 1);
    try test__cmpdi2(-4611686018427387904, -4611686018427387904, 1);
    try test__cmpdi2(-1, -1, 1);
    try test__cmpdi2(0, 0, 1);
    try test__cmpdi2(1, 1, 1);
    try test__cmpdi2(4611686018427387903, 4611686018427387903, 1);
    try test__cmpdi2(9223372036854775806, 9223372036854775806, 1);
    try test__cmpdi2(9223372036854775807, 9223372036854775807, 1);
    // 2. cmp intMin,   {        intMin + 1, intMin/2, -1, 0, 1, intMax/2, intMax-1, intMax}
    try test__cmpdi2(-9223372036854775808, -9223372036854775807, 0);
    try test__cmpdi2(-9223372036854775808, -4611686018427387904, 0);
    try test__cmpdi2(-9223372036854775808, -1, 0);
    try test__cmpdi2(-9223372036854775808, 0, 0);
    try test__cmpdi2(-9223372036854775808, 1, 0);
    try test__cmpdi2(-9223372036854775808, 4611686018427387903, 0);
    try test__cmpdi2(-9223372036854775808, 9223372036854775806, 0);
    try test__cmpdi2(-9223372036854775808, 9223372036854775807, 0);
    // 3. cmp intMin+1, {intMin,             intMin/2, -1,0,1, intMax/2, intMax-1, intMax}
    try test__cmpdi2(-9223372036854775807, -9223372036854775808, 2);
    try test__cmpdi2(-9223372036854775807, -4611686018427387904, 0);
    try test__cmpdi2(-9223372036854775807, -1, 0);
    try test__cmpdi2(-9223372036854775807, 0, 0);
    try test__cmpdi2(-9223372036854775807, 1, 0);
    try test__cmpdi2(-9223372036854775807, 4611686018427387903, 0);
    try test__cmpdi2(-9223372036854775807, 9223372036854775806, 0);
    try test__cmpdi2(-9223372036854775807, 9223372036854775807, 0);
    // 4. cmp intMin/2, {intMin, intMin + 1,           -1,0,1, intMax/2, intMax-1, intMax}
    try test__cmpdi2(-4611686018427387904, -9223372036854775808, 2);
    try test__cmpdi2(-4611686018427387904, -9223372036854775807, 2);
    try test__cmpdi2(-4611686018427387904, -1, 0);
    try test__cmpdi2(-4611686018427387904, 0, 0);
    try test__cmpdi2(-4611686018427387904, 1, 0);
    try test__cmpdi2(-4611686018427387904, 4611686018427387903, 0);
    try test__cmpdi2(-4611686018427387904, 9223372036854775806, 0);
    try test__cmpdi2(-4611686018427387904, 9223372036854775807, 0);
    // 5. cmp -1,       {intMin, intMin + 1, intMin/2,    0,1, intMax/2, intMax-1, intMax}
    try test__cmpdi2(-1, -9223372036854775808, 2);
    try test__cmpdi2(-1, -9223372036854775807, 2);
    try test__cmpdi2(-1, -4611686018427387904, 2);
    try test__cmpdi2(-1, 0, 0);
    try test__cmpdi2(-1, 1, 0);
    try test__cmpdi2(-1, 4611686018427387903, 0);
    try test__cmpdi2(-1, 9223372036854775806, 0);
    try test__cmpdi2(-1, 9223372036854775807, 0);
    // 6. cmp 0,        {intMin, intMin + 1, intMin/2, -1,  1, intMax/2, intMax-1, intMax}
    try test__cmpdi2(0, -9223372036854775808, 2);
    try test__cmpdi2(0, -9223372036854775807, 2);
    try test__cmpdi2(0, -4611686018427387904, 2);
    try test__cmpdi2(0, -1, 2);
    try test__cmpdi2(0, 1, 0);
    try test__cmpdi2(0, 4611686018427387903, 0);
    try test__cmpdi2(0, 9223372036854775806, 0);
    try test__cmpdi2(0, 9223372036854775807, 0);
    // 7. cmp 1,        {intMin, intMin + 1, intMin/2, -1,0,  intMax/2, intMax-1, intMax}
    try test__cmpdi2(1, -9223372036854775808, 2);
    try test__cmpdi2(1, -9223372036854775807, 2);
    try test__cmpdi2(1, -4611686018427387904, 2);
    try test__cmpdi2(1, -1, 2);
    try test__cmpdi2(1, 0, 2);
    try test__cmpdi2(1, 4611686018427387903, 0);
    try test__cmpdi2(1, 9223372036854775806, 0);
    try test__cmpdi2(1, 9223372036854775807, 0);
    // 8. cmp intMax/2, {intMin, intMin + 1, intMin/2, -1,0,1,           intMax-1, intMax}
    try test__cmpdi2(4611686018427387903, -9223372036854775808, 2);
    try test__cmpdi2(4611686018427387903, -9223372036854775807, 2);
    try test__cmpdi2(4611686018427387903, -4611686018427387904, 2);
    try test__cmpdi2(4611686018427387903, -1, 2);
    try test__cmpdi2(4611686018427387903, 0, 2);
    try test__cmpdi2(4611686018427387903, 1, 2);
    try test__cmpdi2(4611686018427387903, 9223372036854775806, 0);
    try test__cmpdi2(4611686018427387903, 9223372036854775807, 0);
    // 9. cmp intMax-1, {intMin, intMin + 1, intMin/2, -1,0,1, intMax/2,           intMax}
    try test__cmpdi2(9223372036854775806, -9223372036854775808, 2);
    try test__cmpdi2(9223372036854775806, -9223372036854775807, 2);
    try test__cmpdi2(9223372036854775806, -4611686018427387904, 2);
    try test__cmpdi2(9223372036854775806, -1, 2);
    try test__cmpdi2(9223372036854775806, 0, 2);
    try test__cmpdi2(9223372036854775806, 1, 2);
    try test__cmpdi2(9223372036854775806, 4611686018427387903, 2);
    try test__cmpdi2(9223372036854775806, 9223372036854775807, 0);
    // 10.cmp intMax,   {intMin, intMin + 1, intMin/2, -1,0,1, intMax/2, intMax-1,       }
    try test__cmpdi2(9223372036854775807, -9223372036854775808, 2);
    try test__cmpdi2(9223372036854775807, -9223372036854775807, 2);
    try test__cmpdi2(9223372036854775807, -4611686018427387904, 2);
    try test__cmpdi2(9223372036854775807, -1, 2);
    try test__cmpdi2(9223372036854775807, 0, 2);
    try test__cmpdi2(9223372036854775807, 1, 2);
    try test__cmpdi2(9223372036854775807, 4611686018427387903, 2);
    try test__cmpdi2(9223372036854775807, 9223372036854775806, 2);
}
