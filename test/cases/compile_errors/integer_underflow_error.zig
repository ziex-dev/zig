export fn entry() void {
    _ = @as(*anyopaque, @ptrFromInt(~@as(usize, @import("std").math.intMax(usize)) - 1));
}

// error
//
// :2:84: error: overflow of integer type 'usize' with value '-1'
