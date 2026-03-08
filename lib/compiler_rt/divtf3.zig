const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const shared_div = @import("div.zig");

comptime {
    if (compiler_rt.want_ppc_abi) {
        symbol(&__divtf3, "__divkf3");
    } else if (compiler_rt.want_sparc_abi) {
        symbol(&_Qp_div, "_Qp_div");
    }
    symbol(&__divtf3, "__divtf3");
}

pub fn __divtf3(a: f128, b: f128) callconv(.c) f128 {
    return shared_div.div128(a, b);
}

fn _Qp_div(c: *f128, a: *const f128, b: *const f128) callconv(.c) void {
    c.* = shared_div.div128(a.*, b.*);
}

test {
    _ = @import("divtf3_test.zig");
}
