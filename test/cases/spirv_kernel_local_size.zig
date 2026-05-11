// Test spirv_kernel calling convention with local_size options

// Using .kernel alias (defaults to 1,1,1)
export fn kernel_alias() callconv(.kernel) void {}

// Explicit default
export fn kernel_explicit_default() callconv(.{ .spirv_kernel = .{} }) void {}

// Custom 1D workgroup
export fn kernel_1d() callconv(.{ .spirv_kernel = .{ .local_size_x = 64 } }) void {}

// Custom 3D workgroup
export fn kernel_3d() callconv(.{ .spirv_kernel = .{ .local_size_x = 8, .local_size_y = 8, .local_size_z = 4 } }) void {}

// compile
// output_mode=Obj
// backend=selfhosted
// target=spirv64-vulkan
// emit_bin=false
