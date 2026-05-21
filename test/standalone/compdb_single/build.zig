const std = @import("std");

const JsonTestTarget = struct {
    name: []const u8,
    kind: enum { exe, lib, obj, @"test" },
    add_c_source: ?[]const u8,
    add_c_source_flags: []const []const u8,
    add_c_sources: []const []const u8,
    add_c_sources_flags: []const []const u8,
};

fn excluded(comptime sources: []const []const u8, inputs: []const []const u8, alloc: std.mem.Allocator) []const []const u8 {
    var excluded_strs: std.ArrayList([]const u8) = .empty;
    defer excluded_strs.deinit(alloc);
    lp: for (sources) |src| {
        for (inputs) |v| {
            if (std.mem.eql(u8, src, v)) continue :lp;
        }
        excluded_strs.append(alloc, src) catch @panic("OOM");
    }
    return excluded_strs.toOwnedSlice(alloc) catch @panic("OOM");
}

const all_sources: []const []const u8 = &.{ "foo.c", "bar.c", "baz.c" };
fn excludedFiles(inputs: []const []const u8, alloc: std.mem.Allocator) []const []const u8 {
    return excluded(all_sources, inputs, alloc);
}

const all_flags: []const []const u8 = &.{ "-Wall", "-Werror", "-Wno-pedantic" };
fn excludedFlags(inputs: []const []const u8, alloc: std.mem.Allocator) []const []const u8 {
    return excluded(all_flags, inputs, alloc);
}

fn expectationsFromTestTarget(comptime test_target: JsonTestTarget, alloc: std.mem.Allocator) CheckCompDb.Options {
    var expected_props: std.ArrayList(CheckCompDb.ExpectedFileProperties) = .empty;
    defer expected_props.deinit(alloc);

    if (test_target.add_c_source) |acc| {
        expected_props.append(alloc, .{
            .source_file_path = acc,
            .expected_flags = test_target.add_c_source_flags,
            .excluded_flags = excludedFlags(test_target.add_c_source_flags, alloc),
        }) catch @panic("OOM");
    }

    for (test_target.add_c_sources) |csrc| {
        expected_props.append(alloc, .{
            .source_file_path = csrc,
            .expected_flags = test_target.add_c_sources_flags,
            .excluded_flags = excludedFlags(test_target.add_c_sources_flags, alloc),
        }) catch @panic("OOM");
    }

    return .{
        .expected_files = expected_props.toOwnedSlice(alloc) catch @panic("OOM"),
        .excluded_files = excludedFiles((if (test_target.add_c_source) |acc| .{acc} else .{}) ++ test_target.add_c_sources, alloc),
    };
}

const test_targets: []const JsonTestTarget = &.{
    // Simple test cases ensuring flags + files are captured as expected
    .{
        .name = "exe",
        .kind = .exe,
        .add_c_source = "foo.c",
        .add_c_source_flags = &.{"-Wall"},
        .add_c_sources = &.{ "bar.c", "baz.c" },
        .add_c_sources_flags = &.{ "-Wall", "-Werror" },
    },
    .{
        .name = "lib",
        .kind = .lib,
        .add_c_source = "foo.c",
        .add_c_source_flags = &.{"-Wno-pedantic"},
        .add_c_sources = &.{"baz.c"},
        .add_c_sources_flags = &.{"-Wall"},
    },
    .{
        .name = "obj",
        .kind = .obj,
        .add_c_source = "foo.c",
        .add_c_source_flags = &.{"-Wno-pedantic"},
        .add_c_sources = &.{"baz.c"},
        .add_c_sources_flags = &.{"-Wall"},
    },
    .{
        .name = "test",
        .kind = .@"test",
        .add_c_source = "bar.c",
        .add_c_source_flags = &.{"-Werror"},
        .add_c_sources = &.{"foo.c"},
        .add_c_sources_flags = &.{},
    },
    // Empty (no C sources) compile_commands.json, returns a compile_commands.json of "[]"
    .{
        .name = "exe_empty",
        .kind = .exe,
        .add_c_source = null,
        .add_c_source_flags = &.{},
        .add_c_sources = &.{},
        .add_c_sources_flags = &.{},
    },
    .{
        .name = "lib_empty",
        .kind = .lib,
        .add_c_source = null,
        .add_c_source_flags = &.{},
        .add_c_sources = &.{},
        .add_c_sources_flags = &.{},
    },
    .{
        .name = "obj_empty",
        .kind = .obj,
        .add_c_source = null,
        .add_c_source_flags = &.{},
        .add_c_sources = &.{},
        .add_c_sources_flags = &.{},
    },
    .{
        .name = "test_empty",
        .kind = .@"test",
        .add_c_source = null,
        .add_c_source_flags = &.{},
        .add_c_sources = &.{},
        .add_c_sources_flags = &.{},
    },
};

pub fn build(b: *std.Build) !void {
    const optimize: std.builtin.OptimizeMode = .Debug;

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    // Single Step.Compile compile_commands.json for sources + no sources
    inline for (test_targets) |test_target| {
        const root_mod = b.createModule(
            .{
                .root_source_file = switch (test_target.kind) {
                    .exe, .@"test" => b.path("main.zig"),
                    // Make sure there's at least something to link for the object/library when adding no C sources
                    // to test empty compile_commands.json behavior
                    else => b.path("obj_or_lib.zig"),
                },
                .target = b.graph.host,
                .optimize = optimize,
            },
        );
        if (test_target.add_c_source) |acc| {
            root_mod.addCSourceFile(.{
                .file = b.path(acc),
                .flags = test_target.add_c_source_flags,
            });
        }
        if (test_target.add_c_sources.len > 0) {
            root_mod.addCSourceFiles(.{
                .files = test_target.add_c_sources,
                .flags = test_target.add_c_sources_flags,
            });
        }

        const compile = switch (test_target.kind) {
            .exe => b.addExecutable(.{
                .name = test_target.name,
                .root_module = root_mod,
                .enable_compdb = true,
            }),
            .obj => b.addObject(.{
                .name = test_target.name,
                .root_module = root_mod,
                .enable_compdb = true,
            }),
            .lib => b.addLibrary(.{
                .name = test_target.name,
                .root_module = root_mod,
                .enable_compdb = true,
            }),
            .@"test" => b.addTest(.{
                .name = test_target.name,
                .root_module = root_mod,
                .enable_compdb = true,
            }),
        };

        const output_json = compile.getCompileCommandsJson() orelse @panic("Expecting enable_comdb");
        const check_json: *CheckCompDb = .create(b, output_json, expectationsFromTestTarget(test_target, b.allocator));
        test_step.dependOn(&check_json.step);
    }
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
