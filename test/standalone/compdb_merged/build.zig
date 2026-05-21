const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize: std.builtin.OptimizeMode = .Debug;
    const target = b.graph.host;

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    // From here on out, all created Step.Compile will default to producing compile_commands.json,
    b.enable_compdb = true;

    const exe = b.addExecutable(.{
        .name = "exe_merged",
        .root_module = b.createModule(
            .{
                .root_source_file = b.path("main.zig"),
                .target = target,
                .optimize = optimize,
            },
        ),
    });
    exe.root_module.addCSourceFile(.{
        .file = b.path("foo.c"),
        .flags = &.{"-Wall"},
    });

    const lib = b.addLibrary(.{
        .name = "lib_merged",
        .root_module = b.createModule(.{
            .root_source_file = b.path("obj_or_lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.addCSourceFile(.{
        .file = b.path("bar.c"),
        .flags = &.{"-Werror"},
    });

    const obj = b.addObject(.{
        .name = "obj_merged",
        .root_module = b.createModule(.{
            .root_source_file = b.path("obj_or_lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    obj.root_module.addCSourceFile(.{
        .file = b.path("baz.c"),
        .flags = &.{"-Wno-pedantic"},
    });

    const test_exe = b.addTest(.{
        .name = "test_merged",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_exe.root_module.addCSourceFile(.{
        .file = b.path("qux.c"),
        .flags = &.{"-Wno-error"},
    });

    const dep = b.dependency("dep", .{ .target = target, .optimize = optimize });
    _ = dep.artifact("dep");

    // Merged compile_commands.json from sources:
    // - Executable
    // - Object
    // - Library
    // - Test
    // - Dependency
    const merged_json = b.getMergedCompileCommandsJson() orelse @panic("Expected enable_compdb");

    const expected: CheckCompDb.Options = .{
        .expected_files = &.{
            // From exe
            .{
                .source_file_path = "foo.c",
                .expected_flags = &.{"-Wall"},
                .excluded_flags = &.{ "-Werror", "-Wno-error", "-Wno-pedantic" },
            },
            // From lib
            .{
                .source_file_path = "bar.c",
                .expected_flags = &.{"-Werror"},
                .excluded_flags = &.{ "-Wall", "-Wno-error", "-Wno-pedantic" },
            },
            // From obj
            .{
                .source_file_path = "baz.c",
                .expected_flags = &.{"-Wno-pedantic"},
                .excluded_flags = &.{ "-Werror", "-Wno-error", "-Wall" },
            },
            // From test
            .{
                .source_file_path = "qux.c",
                .expected_flags = &.{"-Wno-error"},
                .excluded_flags = &.{ "-Werror", "-Wall", "-Wpedantic" },
            },
            // From dependency
            .{
                .source_file_path = "dep1.c",
                .expected_flags = &.{"-Wall"},
                .excluded_flags = &.{ "-Werror", "-Wno-error", "-Wpedantic" },
            },
            .{
                .source_file_path = "dep2.c",
                .expected_flags = &.{ "-Wall", "-Werror" },
                .excluded_flags = &.{ "-Wno-error", "-Wpedantic" },
            },
        },
        .excluded_files = &.{},
    };

    const check_merged_json: *CheckCompDb = .create(b, merged_json, expected);
    test_step.dependOn(&check_merged_json.step);
}

/// Verifies:
/// - # of JSON entries in compile_commands.json matches length of C files provided (including 0 for empty!)
/// - Each expect C file path has a corresponding match in "file" field
/// - Each excluded C file path does NOT have a match in "file" field
/// - Each C file's flags are present in "arguments" field
/// - Each C file's excluded flags are NOT present in "arguments" field
pub const CheckCompDb = struct {
    step: std.Build.Step,
    source: std.Build.LazyPath,
    expected_files: []const ExpectedFileProperties,
    excluded_files: []const []const u8,

    pub const ExpectedFileProperties = struct {
        source_file_path: []const u8,
        expected_flags: []const []const u8 = &.{},
        excluded_flags: []const []const u8 = &.{},
    };

    pub const Options = struct {
        expected_files: []const ExpectedFileProperties,
        excluded_files: []const []const u8 = &.{},
    };

    pub const CompDbJsonEntry = struct {
        directory: []const u8,
        file: []const u8,
        output: []const u8,
        arguments: []const []const u8,
    };
    pub const CompDbJson = []const CompDbJsonEntry;

    pub fn create(
        owner: *std.Build,
        source: std.Build.LazyPath,
        options: Options,
    ) *CheckCompDb {
        const check_compdb = owner.allocator.create(CheckCompDb) catch @panic("OOM");
        check_compdb.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "CheckCompDb",
                .owner = owner,
                .makeFn = make,
            }),
            .source = source.dupe(owner),
            .expected_files = owner.allocator.dupe(ExpectedFileProperties, options.expected_files) catch @panic("OOM"),
            .excluded_files = owner.allocator.dupe([]const u8, options.excluded_files) catch @panic("OOM"),
        };
        check_compdb.source.addStepDependencies(&check_compdb.step);
        return check_compdb;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const b = step.owner;
        const io = b.graph.io;
        const check_compdb: *CheckCompDb = @fieldParentPtr("step", step);
        try step.addWatchInput(check_compdb.source);

        const src_path = check_compdb.source.getPath2(b, step);
        const json_fh = try std.Io.Dir.cwd().openFile(io, src_path, .{});
        defer json_fh.close(io);
        var rd_buffer: [4096]u8 = undefined;
        var json_f_rdr = json_fh.reader(io, &rd_buffer);

        var json_reader: std.json.Reader = .init(b.allocator, &json_f_rdr.interface);
        defer json_reader.deinit();

        const parsed = std.json.parseFromTokenSource(CompDbJson, b.allocator, &json_reader, .{ .ignore_unknown_fields = false }) catch |err| {
            return step.fail("Unable to parse {s}: {s}", .{ src_path, @errorName(err) });
        };
        defer parsed.deinit();

        // Must specify every file you expect a compile_commands.json entry for
        if (parsed.value.len != check_compdb.expected_files.len) {
            return step.fail(
                "Expected {d} file entries, but {s} contains {d}",
                .{ check_compdb.expected_files.len, src_path, parsed.value.len },
            );
        }

        // Holy nested for loops!

        // Make sure expected files are in JSON
        loop: for (check_compdb.expected_files) |expected| {
            for (parsed.value) |entry| {
                // The relative path is good enough, the entry format is absolute paths
                if (std.mem.find(u8, entry.file, expected.source_file_path)) |_| {
                    // Make sure expected flags are in args
                    loopf: for (expected.expected_flags) |flg| {
                        for (entry.arguments) |arg| {
                            if (std.mem.eql(u8, arg, flg)) {
                                continue :loopf;
                            }
                        }
                        return step.fail(
                            "Didn't find expected flag: {s} for source file: {s} in {s}",
                            .{ flg, expected.source_file_path, src_path },
                        );
                    }

                    // Make sure excluded flags are NOT in args
                    for (expected.excluded_flags) |flg| {
                        for (entry.arguments) |arg| {
                            if (std.mem.eql(u8, arg, flg)) {
                                return step.fail(
                                    "Found excluded flag: {s} for source file: {s} in {s}",
                                    .{ flg, expected.source_file_path, src_path },
                                );
                            }
                        }
                    }
                    continue :loop;
                }
            }
            return step.fail(
                "Didn't find expected source file: {s} in {s}",
                .{ expected.source_file_path, src_path },
            );
        }

        // Make sure no excluded files exist in JSON
        for (check_compdb.excluded_files) |excluded_fp| {
            for (parsed.value) |entry| {
                // The relative path is good enough, the entry format is absolute paths
                if (std.mem.find(u8, entry.file, excluded_fp)) |_| {
                    return step.fail(
                        "Found excluded source file: {s} in {s}",
                        .{ excluded_fp, src_path },
                    );
                }
            }
        }
    }
};
