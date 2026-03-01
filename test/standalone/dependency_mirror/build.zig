const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const tester = b.addExecutable(.{ .name = "dependency_mirror_tester", .root_module = b.createModule(.{
        .root_source_file = b.path("run_test.zig"),
        .target = target,
        .optimize = .Debug,
    }) });

    const run_test = b.addRunArtifact(tester);
    run_test.addArg(b.graph.zig_exe);
    run_test.addFileArg(b.path("."));
    test_step.dependOn(&run_test.step);
}
