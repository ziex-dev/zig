export fn foo(p: *align(1) []u8) *[*]u8 {
    return &p.ptr;
}

export fn bar(p: *align(1) []u8) *usize {
    return &p.len;
}

// error
//
// :2:12: error: expected type '*[*]u8', found '*align(1) [*]u8'
// :2:12: note: pointer alignment '1' cannot cast into pointer alignment '8'
// :1:34: note: function return type declared here
// :6:12: error: expected type '*usize', found '*align(1) usize'
// :6:12: note: pointer alignment '1' cannot cast into pointer alignment '8'
// :5:34: note: function return type declared here
