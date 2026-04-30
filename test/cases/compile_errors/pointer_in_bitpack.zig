const S = bitpack struct {
    ptr: *u32,
};
export fn foo() void {
    _ = @as(S, undefined);
}

const U = bitpack union {
    ptr: *u32,
};
export fn bar() void {
    _ = @as(U, undefined);
}

// error
//
// :2:10: error: bitpack structs cannot contain fields of type '*u32'
// :2:10: note: pointers cannot be directly bit-packed
// :2:10: note: consider using 'usize' and '@intFromPtr'
// :9:10: error: bitpack unions cannot contain fields of type '*u32'
// :9:10: note: pointers cannot be directly bit-packed
// :9:10: note: consider using 'usize' and '@intFromPtr'
