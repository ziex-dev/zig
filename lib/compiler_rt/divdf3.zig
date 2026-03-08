const compiler_rt = @import("../compiler_rt.zig");
const symbol = @import("../compiler_rt.zig").symbol;
const shared_div = @import("div.zig");

comptime {
    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_ddiv, "__aeabi_ddiv");
    } else {
        symbol(&__divdf3, "__divdf3");
    }
}

pub fn __divdf3(a: f64, b: f64) callconv(.c) f64 {
    return shared_div.div64(a, b);
}

fn __aeabi_ddiv(a: f64, b: f64) callconv(.{ .arm_aapcs = .{} }) f64 {
    return shared_div.div64(a, b);
}

test {
    _ = @import("divdf3_test.zig");
}
