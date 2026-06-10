export fn f(p: *align(1) ?u32) *u32 {
    return &p.*.?;
}

// error
//
// :2:12: error: expected type '*u32', found '*align(1) u32'
// :2:12: note: pointer alignment '1' cannot cast into pointer alignment '4'
// :1:32: note: function return type declared here
