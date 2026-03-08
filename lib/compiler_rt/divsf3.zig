const compiler_rt = @import("../compiler_rt.zig");
const symbol = @import("../compiler_rt.zig").symbol;
const shared_div = @import("div.zig");

comptime {
    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_fdiv, "__aeabi_fdiv");
    } else {
        symbol(&__divsf3, "__divsf3");
    }
}

pub fn __divsf3(a: f32, b: f32) callconv(.c) f32 {
    return shared_div.div32(a, b);
}

fn __aeabi_fdiv(a: f32, b: f32) callconv(.{ .arm_aapcs = .{} }) f32 {
    return shared_div.div32(a, b);
}

test {
    _ = @import("divsf3_test.zig");
}
