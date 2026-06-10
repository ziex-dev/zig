const U = union(enum) { a: u32, b: u16 };
export fn f(p: *align(1) U) *u32 {
    return switch (p.*) {
        .a => |*x| return x,
        .b => unreachable,
    };
}

// error
//
// :4:27: error: expected type '*u32', found '*align(1) u32'
// :4:27: note: pointer alignment '1' cannot cast into pointer alignment '4'
// :2:29: note: function return type declared here
