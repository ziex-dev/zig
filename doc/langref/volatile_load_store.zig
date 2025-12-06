fn foo(mmio_ptr: *volatile u8) void {
    mmio_ptr.* = 0; // guaranteed store
    mmio_ptr.* = 1; // guaranteed store
    _ = mmio_ptr.*; // guaranteed load
}

// syntax
