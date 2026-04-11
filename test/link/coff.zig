const std = @import("std");
const Build = std.Build;
const Step = std.Build.Step;

const link = @import("link.zig");
const BuildOptions = link.BuildOptions;
const Options = link.Options;
const addExecutable = link.addExecutable;

pub fn testAll(b: *Build, build_opts: BuildOptions) *Step {
    _ = build_opts;
    const coff_step = b.step("test-coff", "Run COFF tests");
    const x86_64_windows = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .msvc,
    });

    const opts: Options = .{ .target = x86_64_windows, .use_llvm = false };
    coff_step.dependOn(testLinkingZig(b, opts));
    return coff_step;
}

fn addTestStep(b: *Build, comptime prefix: []const u8, opts: Options) *Step {
    return link.addTestStep(b, "coff-" ++ prefix, opts);
}

fn testLinkingZig(b: *Build, opts: Options) *Step {
    const test_step = addTestStep(b, "linking-zig", opts);
    const exe = addExecutable(b, opts, .{ .name = "linking-zig", .zig_source_bytes =
        \\pub fn main() void {}
    });

    const check = exe.checkObject();
    check.checkInHeaders();
    check.checkExact("header");
    check.checkExact("machine AMD64");
    check.checkExact("magic PE32+");
    test_step.dependOn(&check.step);

    const run = b.addRunArtifact(exe);
    test_step.dependOn(&run.step);

    return test_step;
}
