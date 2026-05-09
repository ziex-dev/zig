// Test that boolean bitwise operations use logical opcodes in SPIR-V
// Bug: bit_or/bit_and/xor on bools incorrectly emit OpBitwiseOr/And/Xor
//      instead of OpLogicalOr/And/NotEqual

export fn bool_bit_or() void {
    var a = true;
    _ = &a;
    var b = false;
    _ = &b;
    // This generates .bit_or on bools
    var result = a | b;
    _ = &result;
}

export fn bool_bit_and() void {
    var a = true;
    _ = &a;
    var b = false;
    _ = &b;
    // This generates .bit_and on bools
    var result = a & b;
    _ = &result;
}

export fn bool_bit_xor() void {
    var a = true;
    _ = &a;
    var b = false;
    _ = &b;
    // This generates .xor on bools
    var result = a ^ b;
    _ = &result;
}

// Division triggers safety checks that use bool OR
export fn div_safety_check() void {
    var a: i32 = 10;
    _ = &a;
    var b: i32 = 3;
    _ = &b;
    // @divTrunc generates overflow check: (a != MIN) | (b != -1)
    var result = @divTrunc(a, b);
    _ = &result;
}

// compile
// output_mode=Obj
// backend=selfhosted
// target=spirv64-vulkan
// emit_bin=false
