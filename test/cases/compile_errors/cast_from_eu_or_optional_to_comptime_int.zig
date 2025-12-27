comptime {
    const eu: anyerror!u8 = 10;
    const i: comptime_int = eu;
    _ = i;
}

comptime {
    const op: ?u8 = 10;
    const i: comptime_int = op;
    _ = i;
}

// error
//
// :3:29: error: expected type 'comptime_int', found 'anyerror!u8'
// :9:29: error: expected type 'comptime_int', found '?u8'
