// Test that arrays in function variables don't get ArrayStride decoration.
// ArrayStride is only valid on buffer-backed storage classes (uniform,
// push_constant, storage_buffer), not on Function storage class.
// Regression test for #31925.

export fn local_array() void {
    var arr = [_]f32{ 1.0, 2.0, 3.0 };
    _ = &arr;
    var x = arr[0];
    _ = &x;
}

export fn local_array_loop() void {
    var arr = [_]i32{ 10, 20, 30, 40 };
    _ = &arr;
    var sum: i32 = 0;
    for (arr) |val| {
        sum += val;
    }
    _ = &sum;
}

// compile
// output_mode=Obj
// backend=selfhosted
// target=spirv64-vulkan
// emit_bin=false
