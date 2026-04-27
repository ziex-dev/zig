// Regression test for https://codeberg.org/ziglang/zig/issues/32106
//
// Verifies that a TSan-enabled binary can start up when linked against a
// shared library whose constructor calls malloc(). This requires the TSan
// runtime to be initialized before any shared library constructors run.

extern fn lib_function() c_int;

pub fn main() void {
    if (lib_function() != 42) @panic("unexpected return value from lib_function");
}
