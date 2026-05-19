const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const exe_names: []const []const u8 = &.{ "test", "test-dync" };
    const lib_names: []const []const u8 = &.{ "mathtest", "mathtest-dync" };
    const lib_link_libc: []const bool = &.{ false, true };

    for (exe_names, lib_names, lib_link_libc) |exe_name, lib_name, dyn_libc| {
        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = lib_name,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .root_module = b.createModule(.{
                .root_source_file = b.path("mathtest.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = dyn_libc,
            }),
        });

        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_module = b.createModule(.{
                .root_source_file = null,
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        exe.root_module.addCSourceFile(.{
            .file = b.path("test.c"),
            .flags = &[_][]const u8{"-std=c99"},
        });
        exe.root_module.linkLibrary(lib);

        const run_cmd = b.addRunArtifact(exe);
        test_step.dependOn(&run_cmd.step);
    }

    const obj = b.addObject(.{
        .name = "zig_root",
        .root_module = b.createModule(.{
            .root_source_file = b.path("link_lib_with_obj_and_exe_with_obj/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "lib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("link_lib_with_obj_and_exe_with_obj/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("link_lib_with_obj_and_exe_with_obj/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addObject(obj);
    exe.root_module.linkLibrary(lib);
    obj.root_module.linkLibrary(lib);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
