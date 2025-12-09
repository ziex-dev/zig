fn foo() anyerror!u32 {
    return undefined;
}

fn bar() anyerror {
    return undefined;
}

comptime {
    _ = &foo;
    _ = &bar;
}

// error
//
// :2:5: error: cannot return undefined error union
// :6:5: error: cannot return undefined error set
