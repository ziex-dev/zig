const std = @import("std");

const supported_targets = [_]struct { std.Target.Os.Tag, []const std.Target.Cpu.Arch }{
    // .s390x and mips64(el) fail to build
    .{ .linux, &.{ .aarch64, .aarch64_be, .loongarch64, .powerpc64, .powerpc64le, .riscv64, .x86_64 } },
    .{ .macos, &.{ .aarch64, .x86_64 } },

    // powerpc64, powerpc64le, and riscv64 are not supported by TSan yet.
    .{ .freebsd, &.{ .aarch64, .x86_64 } },

    .{ .netbsd, &.{.x86_64} },

    // TSan doesn't have full support for windows yet.
    // .{ .windows, &.{ .aarch64, .x86_64 } },
};

pub fn build(b: *std.Build) !void {
    const test_step = b.step("test", "Test the program");
    b.default_step = test_step;

    const host = b.graph.host;
    const is_macos = host.result.os.tag == .macos;

    for (supported_targets) |entry| {
        switch (entry[0]) {
            // compiling tsan on macos requires system headers that aren't present during cross-compilation
            .macos => {
                if (!is_macos) continue;
                const target = b.resolveTargetQuery(.{});
                const exe = b.addExecutable(.{
                    .name = b.fmt("tsan_{s}_{s}", .{ @tagName(entry[0]), @tagName(target.result.cpu.arch) }),
                    .root_module = b.createModule(.{
                        .root_source_file = b.path("main.zig"),
                        .target = target,
                        .optimize = .Debug,
                        .sanitize_thread = true,
                    }),
                });
                const install_exe = b.addInstallArtifact(exe, .{});
                test_step.dependOn(&install_exe.step);
            },
            else => for (entry[1]) |arch| {
                const target = b.resolveTargetQuery(.{
                    .os_tag = entry[0],
                    .cpu_arch = arch,
                });
                const exe = b.addExecutable(.{
                    .name = b.fmt("tsan_{s}_{s}", .{ @tagName(entry[0]), @tagName(arch) }),
                    .root_module = b.createModule(.{
                        .root_source_file = b.path("main.zig"),
                        .target = target,
                        .optimize = .Debug,
                        .sanitize_thread = true,
                    }),
                });
                const install_exe = b.addInstallArtifact(exe, .{});
                test_step.dependOn(&install_exe.step);
            },
        }
    }

    // Native-only runtime test: verify that a TSan-enabled binary doesn't
    // crash on startup when linked against a shared library whose constructor
    // calls malloc(). Regression test for ziglang/zig#32106. The original bug
    // was for Linux, but this should work on any supported target.

    const host_is_supported = for (supported_targets) |entry| {
        if (entry[0] == host.result.os.tag and
            std.mem.indexOfScalar(std.Target.Cpu.Arch, entry[1], host.result.cpu.arch) != null)
            break true;
    } else false;
    if (host_is_supported) {
        // Build a C shared library with a constructor that calls malloc().
        const tsan_ctor_lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "with_ctor",
            .root_module = b.createModule(.{
                .target = host,
                .link_libc = true,
            }),
        });
        tsan_ctor_lib.root_module.addCSourceFile(.{ .file = b.path("lib_with_ctor.c") });

        // Build a TSan-enabled executable that links the shared library.
        const exe = b.addExecutable(.{
            .name = "tsan_ctor_test",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main_ctor_test.zig"),
                .target = host,
                .optimize = .Debug,
                .sanitize_thread = true,
                .link_libc = true,
            }),
        });
        exe.root_module.linkLibrary(tsan_ctor_lib);

        // Run the binary. Before the fix, this would SIGSEGV during startup.
        const run = b.addRunArtifact(exe);
        test_step.dependOn(&run.step);
    }
}
