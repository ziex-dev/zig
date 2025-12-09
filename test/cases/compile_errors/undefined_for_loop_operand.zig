export fn foo() void {
    for (@as([]const u8, undefined)) |_| {}
}

// error
//
// :2:10: error: use of undefined value here causes illegal behavior
