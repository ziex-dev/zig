comptime {
    const a: anyerror!bool = undefined;
    _ = a catch {};
}

// error
//
// :3:9: error: use of undefined value here causes illegal behavior
