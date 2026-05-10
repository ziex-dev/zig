// Test that arrays in function variables don't get ArrayStride decoration.
// ArrayStride is only valid on buffer-backed storage classes (uniform,
// push_constant, storage_buffer), not on Function storage class.
// Regression test for #31925.

export fn local_array() callconv(.spirv_fragment) void {
    var arr = [_]f32{ 1.0, 2.0, 3.0 };
    _ = &arr;
    var x = arr[0];
    _ = &x;
}

export fn local_array_loop() callconv(.spirv_fragment) void {
    var arr = [_]i32{ 10, 20, 30, 40 };
    _ = &arr;
    var sum: i32 = 0;
    for (arr) |val| {
        sum += val;
    }
    _ = &sum;
}

// Edge case: same array type in both Function and StorageBuffer contexts.
// The fix creates separate type IDs so Function arrays don't get ArrayStride.
// Note: validation skipped (emit_bin=false) because StorageBuffer needs
// SPV_KHR_storage_buffer_storage_class extension which is a separate fix.
extern var global_arr: [4]i32 addrspace(.global);

export fn shared_array_type() callconv(.spirv_fragment) void {
    // Function-local [4]i32 - must NOT get ArrayStride
    var local_arr = [_]i32{ 1, 2, 3, 4 };
    _ = &local_arr;
    // StorageBuffer [4]i32 - separate type ID with ArrayStride
    var x = global_arr[0];
    _ = &x;
}

// compile
// output_mode=Obj
// backend=selfhosted
// target=spirv64-vulkan
// emit_bin=false
