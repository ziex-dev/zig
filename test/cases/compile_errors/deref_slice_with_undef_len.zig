export fn entry1() *const [3]u16 {
    comptime var slice: []const u16 = &.{ 1, 2, 3 };
    slice.len = undefined;
    return slice;
}

export fn entry2() void {
    comptime var slice: []const u8 = "hello";
    slice.len = undefined;
    @compileError(slice);
}

// error
//
// :4:12: error: slice with undefined length cannot cast into array pointer type '*const [3]u16'
// :4:12: note: length of slice must be defined and match length of array type
// :10:19: error: use of slice with undefined length here causes illegal behavior
