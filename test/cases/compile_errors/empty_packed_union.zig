export fn foo() void {
    const U = bitpack union {};
    _ = @as(U, undefined);
}

// error
//
// :2:22: error: packed union has no fields
