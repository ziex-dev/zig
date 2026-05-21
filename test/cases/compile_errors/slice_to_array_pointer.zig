export fn entry1() void {
    var array: [2]u16 = .{ 1, 2 };
    const slice: []const u16 = &array;
    foo(slice);
}

export fn entry2() void {
    const slice: []const u16 = undefined;
    foo(slice);
}

export fn entry3() void {
    comptime var slice: []const u16 = &.{ 1, 2 };
    slice.len = undefined;
    foo(slice);
}

export fn entry4() void {
    const slice: []const u16 = &.{ 1, 2, 3 };
    foo(slice);
}

fn foo(x: *const [2]u16) void {
    _ = x;
}

// error
//
// :4:9: error: coercion from slice to array pointer type '*const [2]u16' requires length to be known at compile-time
// :9:9: error: slice with undefined length cannot cast into array pointer type '*const [2]u16'
// :9:9: note: length of slice must be defined and match length of array type
// :15:9: error: slice with undefined length cannot cast into array pointer type '*const [2]u16'
// :15:9: note: length of slice must be defined and match length of array type
// :20:9: error: slice of length 3 cannot cast into array pointer type '*const [2]u16'
// :20:9: note: length of slice must match length of array type
