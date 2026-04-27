const S = struct { a: u32 };
export fn entry0() void {
    _ = @sizeOf(bitpack union {
        foo: S,
        bar: bool,
    });
}
export fn entry1() void {
    _ = @sizeOf(bitpack union {
        x: *const u32,
    });
}

// error
//
// :4:14: error: bitpack unions cannot contain fields of type 'tmp.S'
// :4:14: note: non-bitpack structs do not have a bit-packed representation
// :1:11: note: struct declared here
// :10:12: error: bitpack unions cannot contain fields of type '*const u32'
// :10:12: note: pointers cannot be directly bitpacked
// :10:12: note: consider using 'usize' and '@intFromPtr'
