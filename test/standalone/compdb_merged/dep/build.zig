const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "dep",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .enable_compdb = null,
    });
    lib.root_module.addCSourceFile(.{
        .file = b.path("dep1.c"),
        .flags = &.{"-Wall"},
    });
    lib.root_module.addCSourceFiles(.{ .files = &.{
        "dep2.c",
    }, .flags = &.{
        "-Wall",
        "-Werror",
    } });
    b.installArtifact(lib);
}
