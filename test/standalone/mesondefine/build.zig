const std = @import("std");
const ConfigHeader = std.Build.Step.ConfigHeader;

pub fn build(b: *std.Build) void {
    const config_header = b.addConfigHeader(
        .{
            .style = .{ .meson = b.path("config.h.in") },
            .include_path = "config.h",
        },
        .{
            .trueval = true,
            .falseval = false,
            .noval = null,
            .intval = 42,
            .zeroval = 0,
            .stringval = "hello",
            .defval = void{},
            .identval = .foo,
        },
    );

    const check_exe = b.addExecutable(.{
        .name = "check",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .root_source_file = b.path("check.zig"),
        }),
    });

    const run_check = b.addRunArtifact(check_exe);
    run_check.addFileArg(config_header.getOutputFile());
    run_check.addFileArg(b.path("expected_config.h"));

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;
    test_step.dependOn(&run_check.step);
}
