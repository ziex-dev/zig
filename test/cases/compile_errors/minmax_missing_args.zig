comptime {
    _ = @min(1);
}
comptime {
    _ = @max(1);
}

// error
//
// :2:9: error: expected at least 2 arguments, found 1
// :5:9: error: expected at least 2 arguments, found 1
