const std = @import("std");

// First, build the `lib.zig` into a wasm binary.
// Second, provide this wasm binary to `main.zig` and then run `main.zig`
pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test");
    b.default_step = test_step;

    const lib = b.addExecutable(.{
        .name = "lib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            // ReleaseSmall build prevents debugging related custom sections such as ".debug_loc" from
            // getting added to the wasm binary.
            // This lets our `main.rs` assert that all encountered custom sections were one defined in
            // `lib.zig`.
            .optimize = .ReleaseSmall,
        }),
    });
    lib.entry = .disabled;

    const main = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = b.standardTargetOptions(.{}),
        }),
    });

    const build_options = b.addOptions();
    build_options.addOptionPath("wasm_path", lib.getEmittedBin());
    main.root_module.addOptions("build_options", build_options);

    main.step.dependOn(&lib.step);

    b.installArtifact(lib);
    b.installArtifact(main);

    const run_step = b.addRunArtifact(main);

    b.default_step.dependOn(&run_step.step);
}

