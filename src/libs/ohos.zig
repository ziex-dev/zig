const std = @import("std");
const Allocator = std.mem.Allocator;

const Compilation = @import("../Compilation.zig");

pub fn resolveLibcSourcePath(comp: *Compilation, arena: Allocator, musl_rel_path: []const u8) ![]const u8 {
    if (!std.mem.startsWith(u8, musl_rel_path, "musl/")) return musl_rel_path;

    const ohos_rel_path = try std.fmt.allocPrint(arena, "ohos/{s}", .{
        musl_rel_path["musl/".len..],
    });
    const zig_lib_rel_path = try std.fmt.allocPrint(arena, "libc/{s}", .{ohos_rel_path});
    if (zigLibRelativePathExists(comp, zig_lib_rel_path)) {
        return ohos_rel_path;
    }
    return musl_rel_path;
}

pub fn isO3Path(file_path: []const u8) bool {
    return std.mem.startsWith(u8, file_path, "ohos/src/malloc/") or
        std.mem.startsWith(u8, file_path, "ohos/src/string/") or
        std.mem.startsWith(u8, file_path, "ohos/src/internal/");
}

pub fn addExtraSrcFiles(comp: *Compilation, arena: Allocator, source_table: anytype, add_src_file: anytype) !void {
    for (extra_src_files) |src_file| {
        const zig_lib_rel_path = try std.fmt.allocPrint(arena, "libc/{s}", .{src_file});
        if (!zigLibRelativePathExists(comp, zig_lib_rel_path)) continue;
        if (source_table.contains(src_file)) continue;
        try add_src_file(arena, source_table, src_file);
    }

    inline for (extra_src_dirs) |entry| {
        try addTopLevelDirFiles(comp, arena, source_table, add_src_file, entry);
    }

    inline for (static_src_dirs) |entry| {
        try addTopLevelDirFiles(comp, arena, source_table, add_src_file, entry);
    }

    for (static_libc_src_files) |src_file| {
        const zig_lib_rel_path = try std.fmt.allocPrint(arena, "libc/{s}", .{src_file});
        if (!zigLibRelativePathExists(comp, zig_lib_rel_path)) continue;
        if (source_table.contains(src_file)) continue;
        try add_src_file(arena, source_table, src_file);
    }

    if (comp.getTarget().cpu.arch == .x86_64) {
        try addX8664FreebsdLd128SrcFiles(comp, arena, source_table, add_src_file);
    }
}

pub fn shouldSkipSource(target: *const std.Target, src_file: []const u8) bool {
    if (!target.abi.isOpenHarmony()) return false;
    if (target.cpu.arch != .x86_64) return false;

    return sourceListContains(&x86_64_long_double_override_src_files, src_file) or
        sourceListContains(&x86_64_freebsd_replaced_src_files, src_file);
}

pub fn includeArchName(target: *const std.Target) []const u8 {
    return std.zig.target.openHarmonyArchNameHeaders(target.cpu.arch);
}

pub fn includeAbiName(target: *const std.Target) []const u8 {
    return std.zig.target.openHarmonyAbiNameHeaders(target.abi);
}

pub fn muslFallbackTriple(arena: Allocator, target: *const std.Target, os_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}-{s}-musl", .{
        std.zig.target.muslArchNameHeaders(target.cpu.arch),
        os_name,
    });
}

pub fn appendPreIncludeArgs(
    comp: *Compilation,
    arena: Allocator,
    args: *std.array_list.Managed([]const u8),
    arch_name: []const u8,
) !void {
    try args.appendSlice(&[_][]const u8{
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "arch", arch_name }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "arch", "generic" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "src", "include" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "src", "internal" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "src", "internal", "linux" }),

        "-DCXA_THREAD_USE_TSD",
    });
}

pub fn appendPostIncludeArgs(
    comp: *Compilation,
    arena: Allocator,
    args: *std.array_list.Managed([]const u8),
    triple: []const u8,
    musl_fallback_triple: []const u8,
) !void {
    try args.appendSlice(&[_][]const u8{
        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "include" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "include", "linux" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "ldso" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "ldso", "linux" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "include", triple }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "include", "generic-ohos" }),

        "-I",
        try comp.dirs.zig_lib.join(arena, &.{ "libc", "include", musl_fallback_triple }),
    });
    if (comp.getTarget().cpu.arch == .x86_64) {
        try args.appendSlice(&[_][]const u8{
            "-I",
            try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "freebsd" }),

            "-I",
            try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "freebsd", "include" }),

            "-I",
            try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "freebsd", "src" }),

            "-I",
            try comp.dirs.zig_lib.join(arena, &.{ "libc", "ohos", "freebsd", "amd64" }),
        });
    }
}

pub fn appendCommonCcArgs(target: *const std.Target, args: *std.array_list.Managed([]const u8)) !void {
    try args.appendSlice(&.{
        "-D__GNU_SOURCE=1",
        "-DFEATURE_ICU_LOCALE",
        "-fPIC",
    });

    if (ohosArchDefine(target.cpu.arch)) |define| {
        try args.append(define);
    }
}

pub fn appendCrtCcArgs(target: *const std.Target, args: *std.array_list.Managed([]const u8)) !void {
    try args.append("-fno-stack-protector");

    if (target.cpu.arch == .aarch64) {
        try args.appendSlice(&.{
            "-mbranch-protection=bti",
        });
    }
}

pub fn appendSourceSpecificCcArgs(
    target: *const std.Target,
    args: *std.array_list.Managed([]const u8),
    src_file: []const u8,
) !void {
    if (needsNoStackProtector(target, src_file)) {
        try args.append("-fno-stack-protector");
    }
}


fn zigLibRelativePathExists(comp: *Compilation, rel_path: []const u8) bool {
    comp.dirs.zig_lib.handle.access(comp.io, rel_path, .{}) catch return false;
    return true;
}

fn sourceListContains(list: []const []const u8, src_file: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, src_file)) return true;
    }
    return false;
}

fn ohosArchDefine(arch: std.Target.Cpu.Arch) ?[]const u8 {
    return switch (arch) {
        .arm, .armeb, .thumb, .thumbeb => "-DMUSL_ARM_ARCH",
        .aarch64, .aarch64_be => "-DMUSL_AARCH64_ARCH",
        .x86_64 => "-DMUSL_X86_64_ARCH",
        else => null,
    };
}

fn needsNoStackProtector(target: *const std.Target, src_file: []const u8) bool {
    return switch (target.cpu.arch) {
        .arm, .armeb, .thumb, .thumbeb => sourceListContains(&arm_nossp_src_files, src_file),
        .aarch64, .aarch64_be => sourceListContains(&aarch64_nossp_src_files, src_file),
        .x86_64 => sourceListContains(&x86_64_nossp_src_files, src_file),
        .riscv64 => sourceListContains(&riscv64_nossp_src_files, src_file),
        .loongarch64 => sourceListContains(&loongarch64_nossp_src_files, src_file),
        else => sourceListContains(&generic_nossp_src_files, src_file),
    };
}


const DirEntrySpec = struct {
    path: []const u8,
    suffix: []const u8,
    exclude_files: []const []const u8 = &.{},
};

fn addTopLevelDirFiles(
    comp: *Compilation,
    arena: Allocator,
    source_table: anytype,
    add_src_file: anytype,
    entry: DirEntrySpec,
) !void {
    const dir_rel_path = entry.path;
    const suffix = entry.suffix;
    var dir = comp.dirs.zig_lib.handle.openDir(comp.io, try std.fmt.allocPrint(arena, "libc/{s}", .{dir_rel_path}), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => |e| return e,
    };
    defer dir.close(comp.io);

    var files = std.array_list.Managed([]const u8).init(arena);
    var it = dir.iterate();
    while (try it.next(comp.io)) |dir_entry| {
        if (dir_entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, dir_entry.name, suffix)) continue;
        var excluded = false;
        for (entry.exclude_files) |exclude_file| {
            if (std.mem.eql(u8, dir_entry.name, exclude_file)) {
                excluded = true;
                break;
            }
        }
        if (excluded) continue;
        try files.append(try std.fmt.allocPrint(arena, "{s}/{s}", .{ dir_rel_path, dir_entry.name }));
    }

    for (0..files.items.len) |i| {
        for (i + 1..files.items.len) |j| {
            if (std.mem.order(u8, files.items[i], files.items[j]) == .gt) {
                std.mem.swap([]const u8, &files.items[i], &files.items[j]);
            }
        }
    }

    for (files.items) |src_file| {
        if (source_table.contains(src_file)) continue;
        try add_src_file(arena, source_table, src_file);
    }
}

fn addX8664FreebsdLd128SrcFiles(
    comp: *Compilation,
    arena: Allocator,
    source_table: anytype,
    add_src_file: anytype,
) !void {
    const listed_files = try readX8664FreebsdLd128SrcFiles(comp, arena);
    for (listed_files) |src_file| {
        if (source_table.contains(src_file)) continue;
        try add_src_file(arena, source_table, src_file);
    }
}

fn readX8664FreebsdLd128SrcFiles(comp: *Compilation, arena: Allocator) ![][]const u8 {
    const rel_path = "libc/ohos/freebsd/ld128/Make.files";
    const contents = try comp.dirs.zig_lib.handle.readFileAlloc(comp.io, rel_path, arena, .limited(64 * 1024));

    var listed_files = std.array_list.Managed([]const u8).init(arena);
    var in_conditional_block = false;
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const line_without_comment = line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len];
        const trimmed_line = std.mem.trim(u8, line_without_comment, " \t\r");
        if (trimmed_line.len == 0) continue;

        if (std.mem.startsWith(u8, trimmed_line, "ifneq")) {
            in_conditional_block = true;
            continue;
        }
        if (std.mem.eql(u8, trimmed_line, "endif")) {
            in_conditional_block = false;
            continue;
        }
        if (in_conditional_block) continue;

        var tokens = std.mem.tokenizeAny(u8, trimmed_line, " \t\r");
        while (tokens.next()) |token| {
            if (!std.mem.endsWith(u8, token, ".c")) continue;
            const src_file = try std.fmt.allocPrint(arena, "ohos/freebsd/ld128/{s}", .{token});
            if (sourceListContains(&x86_64_freebsd_ld128_excluded_src_files, src_file)) continue;
            try listed_files.append(src_file);
        }
    }

    for (x86_64_freebsd_ld128_forced_src_files) |src_file| {
        if (sourceListContains(listed_files.items, src_file)) continue;
        try listed_files.append(src_file);
    }

    return listed_files.toOwnedSlice();
}

const generic_nossp_src_files = [_][]const u8{
    "ohos/src/env/__init_tls.c",
    "ohos/src/env/__libc_start_main.c",
    "ohos/src/env/__stack_chk_fail.c",
};

const arm_nossp_src_files = [_][]const u8{
    "ohos/src/env/__init_tls.c",
    "ohos/src/env/__libc_start_main.c",
    "ohos/src/env/__stack_chk_fail.c",
    "ohos/src/thread/arm/__set_thread_area.c",
};

const aarch64_nossp_src_files = [_][]const u8{
    "ohos/src/env/__init_tls.c",
    "ohos/src/env/__libc_start_main.c",
    "ohos/src/env/__stack_chk_fail.c",
    "ohos/src/thread/aarch64/__set_thread_area.s",
};

const x86_64_nossp_src_files = [_][]const u8{
    "ohos/src/env/__init_tls.c",
    "ohos/src/env/__libc_start_main.c",
    "ohos/src/env/__stack_chk_fail.c",
    "ohos/src/thread/x86_64/__set_thread_area.s",
    "ohos/src/string/memset.c",
};

const riscv64_nossp_src_files = [_][]const u8{
    "ohos/src/env/__init_tls.c",
    "ohos/src/env/__libc_start_main.c",
    "ohos/src/env/__stack_chk_fail.c",
    "ohos/src/thread/riscv64/__set_thread_area.s",
    "ohos/src/string/memset.c",
};

const loongarch64_nossp_src_files = [_][]const u8{
    "ohos/src/env/__init_tls.c",
    "ohos/src/env/__libc_start_main.c",
    "ohos/src/env/__stack_chk_fail.c",
    "ohos/src/thread/loongarch64/__set_thread_area.s",
    "ohos/src/string/memset.c",
};

const extra_src_dirs = [_]DirEntrySpec{
    .{ .path = "ohos/src/fdsan", .suffix = ".c" },
    .{ .path = "ohos/src/fortify", .suffix = ".c" },
    .{ .path = "ohos/src/gwp_asan", .suffix = ".c" },
    .{ .path = "ohos/src/hilog", .suffix = ".c" },
    .{ .path = "ohos/src/hook", .suffix = ".c" },
    .{ .path = "ohos/src/info", .suffix = ".c" },
    .{ .path = "ohos/src/trace", .suffix = ".c" },
    .{ .path = "ohos/src/syscall_hooks", .suffix = ".c" },
    .{ .path = "ohos/src/misc/aarch64", .suffix = ".s" },
};

const extra_src_files = [_][]const u8{
    "ohos/src/internal/musl_log.c",
    "ohos/src/internal/linux/vdso.c",
    "ohos/src/exit/cxa_thread_atexit_impl.c",
    "ohos/src/linux/getprocpid.c",
    "ohos/src/ldso/arm/dlvsym.s",
    "ohos/src/ldso/aarch64/dlvsym.s",
    "ohos/src/ldso/x86_64/dlvsym.s",
    "ohos/src/malloc/stats.c",
    "ohos/src/sigchain/sigchain.c",
};

const static_src_dirs = [_]DirEntrySpec{
    .{ .path = "ohos/src/malloc", .suffix = ".c", .exclude_files = &.{"stats.c"} },
    .{ .path = "ohos/src/malloc/linux", .suffix = ".c", .exclude_files = &.{"stats.c"} },
    .{ .path = "ohos/src/malloc/oldmalloc", .suffix = ".c" },
};

const static_libc_src_files = [_][]const u8{
    "ohos/src/unistd/close.c",
};

const x86_64_freebsd_ld128_excluded_src_files = [_][]const u8{
    "ohos/freebsd/ld128/s_exp2l.c",
};

const x86_64_freebsd_ld128_forced_src_files = [_][]const u8{
    "ohos/freebsd/ld128/lgammal_wrapper.c",
};

const x86_64_long_double_override_src_files = [_][]const u8{
    "musl/src/math/x86_64/__invtrigl.s",
    "musl/src/math/x86_64/acosl.s",
    "musl/src/math/x86_64/asinl.s",
    "musl/src/math/x86_64/atan2l.s",
    "musl/src/math/x86_64/atanl.s",
    "musl/src/math/x86_64/ceill.s",
    "musl/src/math/x86_64/exp2l.s",
    "musl/src/math/x86_64/expl.s",
    "musl/src/math/x86_64/expm1l.s",
    "musl/src/math/x86_64/floorl.s",
    "musl/src/math/x86_64/fmodl.c",
    "musl/src/math/x86_64/llrintl.c",
    "musl/src/math/x86_64/log10l.s",
    "musl/src/math/x86_64/log1pl.s",
    "musl/src/math/x86_64/log2l.s",
    "musl/src/math/x86_64/logl.s",
    "musl/src/math/x86_64/lrintl.c",
    "musl/src/math/x86_64/remainderl.c",
    "musl/src/math/x86_64/remquol.c",
    "musl/src/math/x86_64/rintl.c",
    "musl/src/math/x86_64/sqrtl.c",
    "musl/src/math/x86_64/truncl.s",
};

const x86_64_freebsd_replaced_src_files = [_][]const u8{
    "musl/src/math/acoshl.c",
    "musl/src/math/asinhl.c",
    "musl/src/math/atanhl.c",
    "musl/src/math/coshl.c",
    "musl/src/math/erfl.c",
    "musl/src/math/expl.c",
    "musl/src/math/expm1l.c",
    "musl/src/math/lgammal.c",
    "musl/src/math/log10l.c",
    "musl/src/math/log1pl.c",
    "musl/src/math/log2l.c",
    "musl/src/math/logl.c",
    "musl/src/math/powl.c",
    "musl/src/math/sinhl.c",
    "musl/src/math/tanhl.c",
    "musl/src/math/tgammal.c",
};
