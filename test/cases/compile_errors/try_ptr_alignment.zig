fn f(p: *align(1) (anyerror!u32)) anyerror!*u32 {
    return &(try p.*);
}
comptime {
    _ = &f;
}

// error
//
// :2:12: error: expected type 'anyerror!*u32', found '*align(1) u32'
// :2:12: note: pointer alignment '1' cannot cast into pointer alignment '4'
// :1:43: note: function return type declared here
