const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    // On wasm32, old-style C functions f() should translate as non-variadic fn()
    {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("old_style.h"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .emscripten,
            }),
            .optimize = .Debug,
        });

        const check_wasm = translate_c.addCheckFile(&.{
            "pub const fn_ptr_old_style = ?*const fn () callconv(.c) c_int;",
            "pub const fn_ptr_void = ?*const fn () callconv(.c) c_int;",
            "pub extern fn no_proto_func() c_int;",
            "create_thing: ?*const fn () callconv(.c) c_int",
        });
        test_step.dependOn(&check_wasm.step);
    }

    // On native, old-style () should remain variadic
    {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("old_style.h"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
            }),
            .optimize = .Debug,
        });

        const check_native = translate_c.addCheckFile(&.{
            "pub const fn_ptr_old_style = ?*const fn (...) callconv(.c) c_int;",
            "pub const fn_ptr_void = ?*const fn () callconv(.c) c_int;",
            "pub extern fn no_proto_func(...) c_int;",
            "create_thing: ?*const fn (...) callconv(.c) c_int",
        });
        test_step.dependOn(&check_native.step);
    }
}
