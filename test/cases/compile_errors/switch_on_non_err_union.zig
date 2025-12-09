export fn foo() void {
    false catch |err| switch (err) {
        else => {},
    };
}

// error
//
// :2:5: error: expected error union type, found 'bool'
