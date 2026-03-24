//! Build the OHOS header overlay consumed by Zig's OHOS libc build path.
//!
//! Purpose:
//! - Input 1: OHOS SDK sysroot headers, usually `.../native/sysroot/usr/include`
//! - Input 2: Zig's generic musl headers, usually `lib/libc/musl`
//! - Output: a minimized overlay tree to be copied into `lib/libc/include`
//!
//! The output is split into:
//! - target-specific directories:
//!   - `aarch64-linux-ohos/`
//!   - `arm-linux-ohoseabi/`
//!   - `x86_64-linux-ohos/`
//! - shared directory:
//!   - `generic-ohos/`
//!
//! CLI:
//! - `--search-path <dir>`: OHOS SDK sysroot include directory
//! - `--generic-musl-path <dir>`: Zig musl baseline
//! - `--out <dir>`: output directory to generate
//!
//! Important behavior:
//! - cleans only the OHOS-generated subdirectories under `--out` before writing:
//!   - `aarch64-linux-ohos/`
//!   - `arm-linux-ohoseabi/`
//!   - `x86_64-linux-ohos/`
//!   - `generic-ohos/`
//! - safe to point `--out` directly at `lib/libc/include`
//! - repeated `--search-path` arguments are accepted, but the current code only
//!   uses the first one
//! - comparison is normalized:
//!   - CRLF -> LF
//!   - strips `info/application_target_sdk_version.h`
//!   - removes comments
//!   - ignores whitespace for hashing
//!
//! Processing flow:
//! 1. Build musl baseline header maps from:
//!    - `musl/include`
//!    - `musl/arch/generic`
//! 2. For each OHOS target:
//!    - `aarch64-linux-ohos`
//!    - `arm-linux-ohoseabi`
//!    - `x86_64-linux-ohos`
//! 3. Load `musl/arch/$arch` for that target and merge:
//!    `include` + `arch/generic` + `arch/$arch`
//! 4. For every merged relative path, look up the corresponding header in the
//!    OHOS SDK sysroot:
//!    - `bits/*` and `asm/*` are resolved under `<search-path>/<sdk_target>/...`
//!    - other headers are resolved under `<search-path>/...`
//! 5. If the SDK header differs from musl after normalization, keep it.
//! 6. Headers shared by multiple OHOS targets are emitted into `generic-ohos/`;
//!    target-specific ones are emitted into the target directory.
//! 7. Fortify headers from `<search-path>/fortify` are copied into
//!    `generic-ohos/fortify/`.
//!
//! Typical usage from the repo root:
//! `zig run tools/process_headers_ohos.zig -- --search-path /path/to/sdk/packages/ohos-sdk/darwin/native/sysroot/usr/include --generic-musl-path lib/libc/musl --out /tmp/ohos-headers`
//!
//! Direct in-repo regeneration:
//! `zig run tools/process_headers_ohos.zig -- --search-path /path/to/sdk/.../usr/include --generic-musl-path lib/libc/musl --out lib/libc/include`
//!
//! The generated output tree looks like:
//! - `aarch64-linux-ohos/`
//! - `arm-linux-ohoseabi/`
//! - `x86_64-linux-ohos/`
//! - `generic-ohos/`

const std = @import("std");
const Io = std.Io;
const Arch = std.Target.Cpu.Arch;
const Abi = std.Target.Abi;
const OsTag = std.Target.Os.Tag;
const assert = std.debug.assert;
const Blake3 = std.crypto.hash.Blake3;

const LibCTarget = struct {
    name: []const u8,
    arch: Arch,
    abi: Abi,
    abi_name: []const u8,
    sdk_target: []const u8,
};

fn is_in_array(value: []const u8, array: []const []const u8) bool {
    for (array) |item| {
        if (std.mem.eql(u8, value, item)) {
            return true;
        }
    }
    return false;
}

const musl_targets = [_]LibCTarget{
    LibCTarget{ .name = "aarch64", .arch = Arch.aarch64, .abi = Abi.ohos, .abi_name = "ohos", .sdk_target = "aarch64-linux-ohos" },
    LibCTarget{ .name = "arm", .arch = Arch.arm, .abi = Abi.ohoseabi, .abi_name = "ohoseabi", .sdk_target = "arm-linux-ohos" },
    LibCTarget{ .name = "x86_64", .arch = Arch.x86_64, .abi = Abi.ohos, .abi_name = "ohos", .sdk_target = "x86_64-linux-ohos" },
};

const Contents = struct {
    bytes: []const u8,
    hit_count: usize,
    hash: []const u8,
    is_generic: bool,
    path: []const u8,
    target: []const u8,

    fn hitCountLessThan(context: void, lhs: *const Contents, rhs: *const Contents) bool {
        _ = context;
        return lhs.hit_count < rhs.hit_count;
    }
};

const HashToContents = std.StringHashMap(Contents);
const generated_output_roots = [_][]const u8{
    "aarch64-linux-ohos",
    "arm-linux-ohoseabi",
    "x86_64-linux-ohos",
    "generic-ohos",
};

fn generateGenericFileMap(
    allocator: std.mem.Allocator,
    io: Io,
    cwd_path: []const u8,
    environ_map: ?*const std.process.Environ.Map,
    generic_musl_path: []const []const u8,
) !HashToContents {
    var musl_hash_content = HashToContents.init(allocator);
    const target_include_dir = try std.fs.path.join(allocator, generic_musl_path);

    var dir_stack = std.array_list.Managed([]const u8).init(allocator);
    defer dir_stack.deinit();
    try dir_stack.append(target_include_dir);

    while (dir_stack.pop()) |full_dir_name| {
        var dir = Io.Dir.cwd().openDir(io, full_dir_name, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue,
            error.AccessDenied => continue,
            else => return err,
        };
        defer dir.close(io);

        var dir_it = dir.iterate();

        while (try dir_it.next(io)) |entry| {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ full_dir_name, entry.name });
            switch (entry.kind) {
                .directory => try dir_stack.append(full_path),
                .file => {
                    const rel_path = try std.fs.path.relative(allocator, cwd_path, environ_map, target_include_dir, full_path);

                    const max_size = 2 * 1024 * 1024 * 1024;
                    const raw_bytes = try Io.Dir.cwd().readFileAlloc(io, full_path, allocator, .limited(max_size));

                    const replaced = try replaceBytes(allocator, raw_bytes, "\r\n", "\n");
                    const normalized = try stripUnneededOhosIncludes(allocator, replaced);
                    const removed_comment = try removeComment(allocator, normalized);
                    const trimmed = try removeSpacesAndLines(allocator, removed_comment);

                    const hash = try allocator.alloc(u8, 32);
                    var inner_hasher = Blake3.init(.{});
                    inner_hasher.update(rel_path);
                    inner_hasher.update(trimmed);
                    inner_hasher.final(hash);

                    std.debug.print("generic: {s}\n", .{rel_path});

                    // use path as key and we just need to check the hash
                    const gop = try musl_hash_content.getOrPut(rel_path);

                    // for generic_musl always be new hash
                    gop.value_ptr.* = Contents{ .bytes = trimmed, .hit_count = 1, .target = "", .hash = hash, .is_generic = false, .path = rel_path };
                },
                else => std.debug.print("warning: weird file: {s}\n", .{full_path}),
            }
        }
    }
    return musl_hash_content;
}

fn replaceBytes(allocator: std.mem.Allocator, input: []const u8, from: []const u8, to: []const u8) ![]u8 {
    var builder = std.array_list.Managed(u8).init(allocator);
    defer builder.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (std.mem.startsWith(u8, input[i..], from)) {
            try builder.appendSlice(to);
            i += from.len;
        } else {
            try builder.append(input[i]);
            i += 1;
        }
    }

    return builder.toOwnedSlice();
}

fn stripUnneededOhosIncludes(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();

    var split = std.mem.splitScalar(u8, content, '\n');
    var first = true;
    while (split.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.eql(u8, trimmed, "#include \"info/application_target_sdk_version.h\"") or
            std.mem.eql(u8, trimmed, "#include <info/application_target_sdk_version.h>"))
        {
            continue;
        }

        if (!first) {
            try output.append('\n');
        }
        first = false;
        try output.appendSlice(line);
    }

    return output.toOwnedSlice();
}

fn removeComment(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    var builder = std.array_list.Managed(u8).init(allocator);
    defer builder.deinit();

    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '/' and i + 1 < content.len and content[i + 1] == '/') {
            // single
            while (i < content.len and content[i] != '\n') {
                i += 1;
            }
        } else if (content[i] == '/' and i + 1 < content.len and content[i + 1] == '*') {
            // multi line
            i += 2;
            while (i + 1 < content.len and !(content[i] == '*' and content[i + 1] == '/')) {
                i += 1;
            }
            i += 2; // skip end of */
        } else {
            // non-comment
            _ = try builder.append(content[i]);
            i += 1;
        }
    }

    return builder.toOwnedSlice();
}

fn removeSpacesAndLines(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, content.len);
    var resultIndex: usize = 0;
    var i: usize = 0;

    while (i < content.len) : (i += 1) {
        const c = content[i];
        const isFullWidthSpace = (i + 2 < content.len) and (content[i] == 0xE3) and (content[i + 1] == 0x80) and (content[i + 2] == 0x80);
        if (std.ascii.isWhitespace(c) or isFullWidthSpace) {} else {
            result[resultIndex] = c;
            resultIndex += 1;
        }
    }

    return result[0..resultIndex];
}

fn fileExists(io: Io, path: []const u8) bool {
    Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn dirExists(io: Io, path: []const u8) bool {
    var dir = Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

fn copyOhosFortifyHeaders(
    allocator: std.mem.Allocator,
    io: Io,
    cwd_path: []const u8,
    environ_map: ?*const std.process.Environ.Map,
    search_path: []const u8,
    out_dir: []const u8,
) !void {
    const fortify_src_dir = try std.fs.path.join(allocator, &[_][]const u8{ search_path, "fortify" });
    if (!dirExists(io, fortify_src_dir)) return;

    var dir_stack = std.array_list.Managed([]const u8).init(allocator);
    defer dir_stack.deinit();
    try dir_stack.append(fortify_src_dir);

    while (dir_stack.pop()) |src_dir| {
        var dir = Io.Dir.cwd().openDir(io, src_dir, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => continue,
            error.AccessDenied => continue,
            else => return err,
        };
        defer dir.close(io);

        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            const src_path = try std.fs.path.join(allocator, &[_][]const u8{ src_dir, entry.name });
            switch (entry.kind) {
                .directory => try dir_stack.append(src_path),
                .file => {
                    const rel = try std.fs.path.relative(allocator, cwd_path, environ_map, fortify_src_dir, src_path);
                    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{
                        out_dir,
                        "generic-ohos",
                        "fortify",
                        rel,
                    });
                    try Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(dst_path).?);

                    const max_size = 2 * 1024 * 1024 * 1024;
                    const raw = try Io.Dir.cwd().readFileAlloc(io, src_path, allocator, .limited(max_size));
                    const replaced = try replaceBytes(allocator, raw, "\r\n", "\n");
                    const normalized = try stripUnneededOhosIncludes(allocator, replaced);
                    const content = std.mem.trimEnd(u8, normalized, "\r\n");
                    const with_newline = try std.mem.concat(allocator, u8, &[_][]const u8{ content, "\n" });
                    defer allocator.free(with_newline);

                    try Io.Dir.cwd().writeFile(io, .{ .sub_path = dst_path, .data = with_newline });
                },
                else => {},
            }
        }
    }
}

fn resetGeneratedOhosRoots(allocator: std.mem.Allocator, io: Io, out_dir: []const u8) !void {
    for (generated_output_roots) |root| {
        const root_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, root });
        defer allocator.free(root_path);
        if (!dirExists(io, root_path)) continue;
        try Io.Dir.cwd().deleteTree(io, root_path);
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(allocator);
    const cwd_path = try std.process.currentPathAlloc(io, allocator);
    const environ_map = init.environ_map;
    var search_paths = std.array_list.Managed([]const u8).init(allocator);
    defer search_paths.deinit();
    var opt_out_dir: ?[]const u8 = null;
    var opt_generic_musl_libc_dir: ?[]const u8 = null;

    var arg_i: usize = 1;
    while (arg_i < args.len) : (arg_i += 1) {
        if (std.mem.eql(u8, args[arg_i], "--help"))
            usageAndExit(args[0]);
        if (arg_i + 1 >= args.len) {
            std.debug.print("expected argument after '{s}'\n", .{args[arg_i]});
            usageAndExit(args[0]);
        }

        if (std.mem.eql(u8, args[arg_i], "--search-path")) {
            try search_paths.append(args[arg_i + 1]);
        } else if (std.mem.eql(u8, args[arg_i], "--out")) {
            assert(opt_out_dir == null);
            opt_out_dir = args[arg_i + 1];
        } else if (std.mem.eql(u8, args[arg_i], "--generic-musl-path")) {
            assert(opt_generic_musl_libc_dir == null);
            opt_generic_musl_libc_dir = args[arg_i + 1];
        } else {
            std.debug.print("unrecognized argument: {s}\n", .{args[arg_i]});
            usageAndExit(args[0]);
        }

        arg_i += 1;
    }

    const out_dir = opt_out_dir orelse usageAndExit(args[0]);
    const generic_musl_libc_dir: []const u8 = opt_generic_musl_libc_dir orelse usageAndExit(args[0]);
    if (search_paths.items.len == 0) usageAndExit(args[0]);

    var max_bytes_saved: usize = 0;
    var total_bytes: usize = 0;

    // Stage 1: build the musl baseline maps used for content de-duplication.
    const musl_hash_to_contents = generateGenericFileMap(allocator, io, cwd_path, environ_map, &[_][]const u8{ generic_musl_libc_dir, "include" }) catch |err| {
        std.debug.print("Error occurred: {}\n", .{err});
        return;
    };
    const musl_generic_hash_content = generateGenericFileMap(allocator, io, cwd_path, environ_map, &[_][]const u8{ generic_musl_libc_dir, "arch", "generic" }) catch |err| {
        std.debug.print("Error occurred: {}\n", .{err});
        return;
    };

    var ohos_common_content = HashToContents.init(allocator);

    // Stage 2: compare each OHOS target header view against the merged musl
    // baseline (`include` + `arch/generic` + `arch/$arch`).
    for (musl_targets) |libc_target| {
        const target = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{
            libc_target.name,
            "linux",
            libc_target.abi_name,
        });

        const arch_generic_hash_content = generateGenericFileMap(allocator, io, cwd_path, environ_map, &[_][]const u8{ generic_musl_libc_dir, "arch", libc_target.name }) catch |err| {
            std.debug.print("Error occurred: {}\n", .{err});
            return;
        };

        // merge hashmap by path
        // arch_generic_hash_content is the most specific and should be merged last
        var result = HashToContents.init(allocator);
        var it1 = musl_hash_to_contents.iterator();
        while (it1.next()) |entry| {
            try result.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var it2 = musl_generic_hash_content.iterator();
        while (it2.next()) |entry| {
            try result.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        var it3 = arch_generic_hash_content.iterator();
        while (it3.next()) |entry| {
            try result.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var iterator = result.iterator();
        // iterate the map and make sure the hash is unique
        while (iterator.next()) |entry| {
            var target_dir: []const u8 = "";

            if (std.mem.startsWith(u8, entry.key_ptr.*, "bits") or std.mem.startsWith(u8, entry.key_ptr.*, "asm")) {
                target_dir = libc_target.sdk_target;
            }
            const target_file_path = try std.fs.path.join(allocator, &[_][]const u8{ search_paths.items[0], target_dir, entry.key_ptr.* });

            if (!fileExists(io, target_file_path)) {
                continue;
            }

            const max_size = 2 * 1024 * 1024 * 1024;
            const raw_bytes = try Io.Dir.cwd().readFileAlloc(io, target_file_path, allocator, .limited(max_size));
            const replaced = try replaceBytes(allocator, raw_bytes, "\r\n", "\n");
            const normalized = try stripUnneededOhosIncludes(allocator, replaced);

            // save content
            const tmp_content = std.mem.trim(u8, normalized, " \r\n\t");

            const removed_content = try removeComment(allocator, normalized);
            const trimmed = try removeSpacesAndLines(allocator, removed_content);

            total_bytes += raw_bytes.len;
            const hash = try allocator.alloc(u8, 32);

            var hasher = Blake3.init(.{});
            hasher.update(entry.key_ptr.*);
            hasher.update(trimmed);
            hasher.final(hash);

            // if hash is the same, we can reduce the size
            if (std.mem.eql(u8, hash, entry.value_ptr.hash)) {
                max_bytes_saved += raw_bytes.len;
                std.debug.print("ohos duplicate: {s} {s} ({:2})\n", .{
                    libc_target.name,
                    entry.key_ptr.*,
                    raw_bytes.len,
                });
            } else {
                const common = try ohos_common_content.getOrPut(hash);

                if (common.found_existing) {
                    common.value_ptr.hit_count += 1;
                } else {
                    common.value_ptr.* = Contents{ .bytes = tmp_content, .target = target, .hit_count = 1, .hash = hash, .is_generic = false, .path = entry.value_ptr.path };
                }
            }
        }
    }

    try Io.Dir.cwd().createDirPath(io, out_dir);
    try resetGeneratedOhosRoots(allocator, io, out_dir);

    // Stage 3: write headers shared by multiple OHOS targets to
    // `generic-ohos`, otherwise keep them target-specific.
    var it = ohos_common_content.iterator();
    while (it.next()) |entry| {
        var full_path: []const u8 = "";
        if (entry.value_ptr.hit_count > 1) {
            full_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, "generic-ohos", entry.value_ptr.path });
        } else {
            full_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, entry.value_ptr.target, entry.value_ptr.path });
        }

        try Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(full_path).?);
        const with_newline = try std.mem.concat(allocator, u8, &[_][]const u8{ entry.value_ptr.bytes, "\n" });
        defer allocator.free(with_newline);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = full_path, .data = with_newline });
    }

    // Stage 4: fortify headers are copied verbatim to the shared overlay tree.
    try copyOhosFortifyHeaders(allocator, io, cwd_path, environ_map, search_paths.items[0], out_dir);
}

fn usageAndExit(arg0: []const u8) noreturn {
    std.debug.print("Usage: {s} --search-path <dir> --generic-musl-path <dir> --out <name>\n", .{arg0});
    std.debug.print("--search-path should be openharmony ndk include dir.\n", .{});
    std.debug.print("--generic-musl-path is current generic-musl dir.\n", .{});
    std.debug.print("--out is a dir that will be created, and populated with the results\n", .{});
    std.process.exit(1);
}
