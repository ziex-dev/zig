const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const step = b.step("test", "Run simple standalone test cases");
    b.default_step = step;

    const skip_debug = b.option(bool, "skip_debug", "Skip debug builds") orelse false;
    const skip_release_safe = b.option(bool, "skip_release_safe", "Skip release-safe builds") orelse false;
    const skip_release_fast = b.option(bool, "skip_release_fast", "Skip release-fast builds") orelse false;
    const skip_release_small = b.option(bool, "skip_release_small", "Skip release-small builds") orelse false;

    var optimize_modes_buf: [4]std.builtin.OptimizeMode = undefined;
    var optimize_modes_len: usize = 0;
    if (!skip_debug) {
        optimize_modes_buf[optimize_modes_len] = .Debug;
        optimize_modes_len += 1;
    }
    if (!skip_release_safe) {
        optimize_modes_buf[optimize_modes_len] = .ReleaseSafe;
        optimize_modes_len += 1;
    }
    if (!skip_release_fast) {
        optimize_modes_buf[optimize_modes_len] = .ReleaseFast;
        optimize_modes_len += 1;
    }
    if (!skip_release_small) {
        optimize_modes_buf[optimize_modes_len] = .ReleaseSmall;
        optimize_modes_len += 1;
    }
    const optimize_modes = optimize_modes_buf[0..optimize_modes_len];

    for (cases) |case| {
        for (optimize_modes) |optimize| {
            if (!case.all_modes and optimize != .Debug) continue;
            if (case.os_filter) |os_tag| {
                if (os_tag != builtin.os.tag) continue;
            }

            const resolved_target = b.resolveTargetQuery(case.target);

            if (case.file_type == .exe or case.file_type == .exe_and_obj) {
                const exe = b.addExecutable(.{
                    .name = std.fs.path.stem(case.src_path),
                    .root_module = b.createModule(.{
                        .root_source_file = b.path(case.src_path),
                        .optimize = optimize,
                        .target = resolved_target,
                        .link_libc = case.link_libc,
                        .strip = case.strip,
                    }),
                    .use_llvm = case.use_llvm,
                    .use_lld = if (builtin.os.tag == .macos) false else case.use_llvm,
                });
                if (case.emit_type == .bin) _ = exe.getEmittedBin();
                if (case.emit_type == .@"asm") _ = exe.getEmittedAsm();
                if (case.emit_type == .llvm_ir_and_llvm_bc) {
                    _ = exe.getEmittedLlvmIr();
                    _ = exe.getEmittedLlvmBc();
                }

                step.dependOn(&exe.step);
            }

            if (case.file_type == .@"test") {
                const exe = b.addTest(.{
                    .name = std.fs.path.stem(case.src_path),
                    .root_module = b.createModule(.{
                        .root_source_file = b.path(case.src_path),
                        .optimize = optimize,
                        .target = resolved_target,
                        .link_libc = case.link_libc,
                        .strip = case.strip,
                    }),
                    .use_llvm = case.use_llvm,
                    .use_lld = if (builtin.os.tag == .macos) false else case.use_llvm,
                });
                if (case.emit_type == .bin) _ = exe.getEmittedBin();
                if (case.emit_type == .@"asm") _ = exe.getEmittedAsm();
                if (case.emit_type == .llvm_ir_and_llvm_bc) {
                    _ = exe.getEmittedLlvmIr();
                    _ = exe.getEmittedLlvmBc();
                }

                const run = b.addRunArtifact(exe);
                step.dependOn(&run.step);
            }

            if (case.file_type == .obj or case.file_type == .exe_and_obj) {
                const obj = b.addObject(.{
                    .name = std.fs.path.stem(case.src_path),
                    .root_module = b.createModule(.{
                        .root_source_file = b.path(case.src_path),
                        .optimize = optimize,
                        .target = resolved_target,
                        .link_libc = case.link_libc,
                        .strip = case.strip,
                    }),
                    .use_llvm = case.use_llvm,
                    .use_lld = if (builtin.os.tag == .macos) false else case.use_llvm,
                });
                if (case.emit_type == .bin) _ = obj.getEmittedBin();
                if (case.emit_type == .@"asm") _ = obj.getEmittedAsm();
                if (case.emit_type == .llvm_ir_and_llvm_bc) {
                    _ = obj.getEmittedLlvmIr();
                    _ = obj.getEmittedLlvmBc();
                }

                step.dependOn(&obj.step);
            }
        }
    }
}

const FileType = enum {
    exe,
    obj,
    exe_and_obj,
    @"test",
};

const EmitType = enum {
    bin,
    @"asm",
    llvm_ir_and_llvm_bc,
};

const Case = struct {
    src_path: []const u8,
    link_libc: bool = false,
    use_llvm: bool = true,
    strip: bool = false,
    all_modes: bool = false,
    target: std.Target.Query = .{},
    file_type: FileType = .exe,
    emit_type: EmitType = .bin,
    /// Run only on this OS.
    os_filter: ?std.Target.Os.Tag = null,
};

const cases = [_]Case{
    .{
        .src_path = "emit_asm_no_bin.zig",
        .file_type = .obj,
        .emit_type = .@"asm",
    },
    .{
        .src_path = "emit_llvm_no_bin.zig",
        .file_type = .obj,
        .emit_type = .llvm_ir_and_llvm_bc,
    },
    .{
        .src_path = "empty_global_error_set.zig",
        .file_type = .obj,
        .target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
        },
    },
    .{
        .src_path = "empty_global_error_set.zig",
        .file_type = .obj,
        .target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
        },
        .use_llvm = false,
    },
    .{
        .src_path = "hello_world/hello.zig",
        .all_modes = true,
    },
    .{
        .src_path = "hello_world/hello_libc.zig",
        .link_libc = true,
        .all_modes = true,
    },
    .{
        .src_path = "issue_5825.zig",
        .file_type = .exe_and_obj,
        .os_filter = .windows,
        .target = .{
            .cpu_arch = .x86_64,
            .abi = .msvc,
        },
    },
    .{
        .src_path = "issue_7030.zig",
        .target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
    },
    .{
        .src_path = "issue_9402.zig",
        .os_filter = .windows,
        .link_libc = true,
    },
    .{
        .src_path = "strip_struct_init.zig",
        .file_type = .@"test",
        .strip = true,
    },
    .{
        .src_path = "zerolength_check.zig",
        .file_type = .@"test",
        .all_modes = true,
        .os_filter = .wasi,
        .target = .{
            .cpu_arch = .wasm32,
            .cpu_features_add = std.Target.wasm.featureSet(&.{.bulk_memory}),
        },
    },
    .{ .src_path = "cat.zig" },
    .{ .src_path = "guess_number.zig" },
    .{ .src_path = "main_return_error/error_u8.zig" },
    .{ .src_path = "main_return_error/error_u8_non_zero.zig" },
    .{ .src_path = "noreturn_call/inline.zig" },
    .{ .src_path = "noreturn_call/as_arg.zig" },
    .{ .src_path = "std_enums_big_enums.zig" },
};
