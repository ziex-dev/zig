const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test colon link");
    b.default_step = test_step;

    // -l:filename is a GNU ld feature; only test on Linux.
    if (builtin.os.tag != .linux) return;

    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = .Debug;

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "mylib",
        .root_module = b.createModule(.{
            .root_source_file = null,
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.addCSourceFile(.{
        .file = b.path("mylib.c"),
    });

    // Link using -l:libmylib.so (colon prefix = exact filename search).
    const exe = b.addExecutable(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = null,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.addCSourceFile(.{
        .file = b.path("main.c"),
    });
    exe.root_module.linkSystemLibrary(":libmylib.so", .{});
    exe.root_module.addLibraryPath(lib.getEmittedBinDirectory());
    exe.root_module.addRPath(lib.getEmittedBinDirectory());

    const run = b.addRunArtifact(exe);
    run.expectStdOutEqual("42\n");
    test_step.dependOn(&run.step);
}
