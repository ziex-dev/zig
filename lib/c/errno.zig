const builtin = @import("builtin");
const std = @import("std");
const symbol = @import("../c.zig").symbol;
const _errno = @import("../c.zig")._errno;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&errno_location, "___errno_location");
        symbol(&errno_location, "__errno_location");
    }

    if (builtin.target.isMinGW()) {}
}

fn errno_location() callconv(.c) *c_int {
    return _errno();
}
