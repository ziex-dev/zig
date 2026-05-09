// Storing a StorageBuffer pointer in a function variable requires variable_pointers capability
export fn needs_variable_pointers() void {
    var x: *addrspace(.global) i32 = undefined;
    _ = &x;
}

// error
// backend=selfhosted
// target=spirv64-vulkan
//
// :2:8: error: storing 'global' pointer in function variable requires 'variable_pointers' target feature
