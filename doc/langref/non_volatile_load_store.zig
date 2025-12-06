fn foo(ptr: *u8) void {
    ptr.* = 0; // redundant store
    ptr.* = 1; // store
    _ = ptr.*; // redundant load
}

// syntax
