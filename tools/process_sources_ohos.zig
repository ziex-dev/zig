//! Build the `lib/libc/ohos` source overlay from an upstream OpenHarmony musl tree.
//!
//! Purpose:
//! - Input 1: an upstream OpenHarmony musl source tree
//! - Input 2: Zig's generic musl baseline, usually `lib/libc/musl`
//! - Output: a minimized overlay tree to be copied into `lib/libc/ohos`
//!
//! This tool does not emit a full musl copy. It emits:
//! - files that differ from generic musl
//! - a few Zig-local generated files
//! - a few mirrored files from generic musl that OHOS still needs
//! - a few repo-maintained supplemental files that upstream OHOS musl does not
//!   carry, such as the `freebsd/` OpenLibm long-double sources used by
//!   `x86_64-linux-ohos`
//!
//! CLI:
//! - `--ohos-musl-path <dir>`: upstream OpenHarmony musl tree
//! - `--generic-musl-path <dir>`: Zig musl baseline
//! - `--out <dir>`: output directory to generate
//!
//! Important behavior:
//! - recommended OHOS source input is a checkout of:
//!   `https://gitcode.com/openharmony/third_party_musl` on branch `master`
//! - deletes `--out` first if it already exists
//! - normalizes CRLF to LF
//! - applies a few hardcoded source fixups before diffing
//! - drops `.c`/`.s`/`.S` files identical to generic musl after normalization
//! - still keeps some identical non-source companion files to preserve layout
//! - filters out unsupported arch-specific directories and all `liteos_a`
//!   paths for the current supported OHOS targets:
//!   `aarch64-linux-ohos`, `arm-linux-ohoseabi`, `x86_64-linux-ohos`
//!
//! Processing flow:
//! 1. Walk the top-level OHOS musl roots:
//!    `arch`, `include`, `src`, `crt`, `ldso`, `compat/time32`
//! 2. For each file:
//!    normalize line endings, apply local fixups, compare against generic musl,
//!    and only emit it if it is different or should always be preserved.
//!    Files under unsupported arch directories or any `liteos_a` directory are
//!    skipped before diffing.
//! 3. Flatten OHOS `.../linux/...` overlay directories back onto canonical musl
//!    destination paths, for example `src/internal/linux -> src/internal`.
//! 4. Generate Zig-local helper files such as `src/malloc/malloc_replaced.c`.
//! 5. Mirror selected generic musl files such as `libc.S`, injecting OHOS
//!    fortify stubs into the mirrored `libc.S`.
//! 6. Copy repo-maintained supplemental OHOS overlay roots such as `freebsd/`.
//!
//! Current built-in textual fixups:
//! - `src/time/gettimeofday.c`
//! - `src/network/getnameinfo.c`
//! - `src/network/lookup_name.c`
//! - `src/network/getaddrinfo.c`
//!
//! Typical usage from the repo root:
//! `zig run tools/process_sources_ohos.zig -- --ohos-musl-path /path/to/openharmony/third_party/musl --generic-musl-path lib/libc/musl --out /tmp/ohos-src`
//!
//! Typical review + sync flow:
//! 1. Generate to a temp directory:
//!    `zig run tools/process_sources_ohos.zig -- --ohos-musl-path /path/to/openharmony/third_party/musl --generic-musl-path lib/libc/musl --out /tmp/ohos-src`
//! 2. Compare with the checked-in overlay:
//!    `diff -ru lib/libc/ohos /tmp/ohos-src`
//! 3. Sync into the repo:
//!    `rsync -a /tmp/ohos-src/ lib/libc/ohos/`
//!
//! The generated output tree looks like:
//! - `arch/`
//! - `crt/`
//! - `include/`
//! - `ldso/`
//! - `src/`
//! - `compat/time32/`
//! - `freebsd/`
//! - `libc.S`

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;

const sync_roots = [_][]const u8{
    "arch",
    "include",
    "src",
    "crt",
    "ldso",
    "compat/time32",
};

const supplemental_roots = [_][]const u8{
    "freebsd",
};

const default_ported_ohos_overlay_path = "lib/libc/ohos";

const OverlayDir = struct {
    source_path: []const u8,
    dest_path: []const u8,
};

const linux_overlay_dirs = [_]OverlayDir{
    .{ .source_path = "src/internal/linux", .dest_path = "src/internal" },
    .{ .source_path = "src/hook/linux", .dest_path = "src/hook" },
    .{ .source_path = "crt/linux", .dest_path = "crt" },
    .{ .source_path = "src/linux/arm/linux", .dest_path = "src/linux/arm" },
    .{ .source_path = "src/linux/aarch64/linux", .dest_path = "src/linux/aarch64" },
    .{ .source_path = "src/linux/x86_64/linux", .dest_path = "src/linux/x86_64" },
    .{ .source_path = "src/exit/linux", .dest_path = "src/exit" },
    .{ .source_path = "src/fdsan/linux", .dest_path = "src/fdsan" },
    .{ .source_path = "src/fortify/linux", .dest_path = "src/fortify" },
    .{ .source_path = "src/gwp_asan/linux", .dest_path = "src/gwp_asan" },
    .{ .source_path = "src/hilog/linux", .dest_path = "src/hilog" },
    .{ .source_path = "src/linux/linux", .dest_path = "src/linux" },
    .{ .source_path = "src/network/linux", .dest_path = "src/network" },
    .{ .source_path = "src/syscall_hooks/linux", .dest_path = "src/syscall_hooks" },
    .{ .source_path = "src/signal/linux", .dest_path = "src/signal" },
    .{ .source_path = "src/thread/linux", .dest_path = "src/thread" },
    .{ .source_path = "src/trace/linux", .dest_path = "src/trace" },
    .{ .source_path = "include/trace/linux", .dest_path = "include/trace" },
    .{ .source_path = "src/info/linux", .dest_path = "src/info" },
    .{ .source_path = "ldso/linux", .dest_path = "ldso" },
    .{ .source_path = "include/sys/linux", .dest_path = "include/sys" },
    .{ .source_path = "include/info/linux", .dest_path = "include/info" },
    .{ .source_path = "include/fortify/linux", .dest_path = "include/fortify" },
    .{ .source_path = "include/linux", .dest_path = "include" },
    .{ .source_path = "src/ldso/arm/linux", .dest_path = "src/ldso/arm" },
    .{ .source_path = "src/ldso/aarch64/linux", .dest_path = "src/ldso/aarch64" },
    .{ .source_path = "src/ldso/x86_64/linux", .dest_path = "src/ldso/x86_64" },
    .{ .source_path = "src/misc/aarch64/linux", .dest_path = "src/misc/aarch64" },
    .{ .source_path = "src/malloc/linux", .dest_path = "src/malloc" },
    .{ .source_path = "src/sigchain/linux", .dest_path = "src/sigchain" },
    .{ .source_path = "scripts/linux", .dest_path = "" },
};

const Stats = struct {
    scanned: usize = 0,
    copied: usize = 0,
    same_as_musl: usize = 0,
};

const GeneratedFile = struct {
    relative_path: []const u8,
    contents: []const u8,
};

const MirroredFile = struct {
    relative_path: []const u8,
    source_relative_path: []const u8,
};

const mirrored_files = [_]MirroredFile{
    .{
        .relative_path = "libc.S",
        .source_relative_path = "libc.S",
    },
};

const generated_files = [_]GeneratedFile{
    .{
        .relative_path = "src/malloc/malloc_replaced.c",
        .contents =
        \\__attribute__((__visibility__("hidden"))) int __malloc_replaced = 0;
        \\__attribute__((__visibility__("hidden"))) int __aligned_alloc_replaced = 0;
        ,
    },
};

fn replaceBytes(allocator: std.mem.Allocator, input: []const u8, from: []const u8, to: []const u8) ![]u8 {
    var builder: std.ArrayList(u8) = .empty;
    defer builder.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (std.mem.startsWith(u8, input[i..], from)) {
            try builder.appendSlice(allocator, to);
            i += from.len;
        } else {
            try builder.append(allocator, input[i]);
            i += 1;
        }
    }

    return builder.toOwnedSlice(allocator);
}

fn normalizeContent(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    return replaceBytes(allocator, raw, "\r\n", "\n");
}

fn applyFixups(allocator: std.mem.Allocator, relative_path: []const u8, input: []const u8) ![]u8 {
    var output = try allocator.dupe(u8, input);

    // Keep the generated overlay self-contained by applying the local fixes
    // that Zig expects today, instead of requiring a patched upstream tree.
    if (std.mem.eql(u8, relative_path, "src/time/gettimeofday.c")) {
        const next = try replaceBytes(allocator, output, "(int (*)(struct timval *, void *))p;", "(int (*)(struct timeval *, void *))p;");
        allocator.free(output);
        output = next;
    }

    if (std.mem.eql(u8, relative_path, "src/network/getnameinfo.c")) {
        const next = try replaceBytes(allocator, output, "static inline int get_hosts_str(char *line, int length, FILE *f, int *i)\n{\n\tif (f) {\n\t\treturn fgets(line, length, f);\n\t}\n\tif (*i < FIXED_HOSTS_MAX_LENGTH) {\n\t\tmemcpy(line, fixed_hosts[*i], strlen(fixed_hosts[*i]));\n\t\t(*i)++;\n\t\treturn 1;\n\t}\n\treturn NULL;\n}\n", "static inline char *get_hosts_str(char *line, int length, FILE *f, int *i)\n{\n\tif (f) {\n\t\treturn fgets(line, length, f);\n\t}\n\tif (*i < FIXED_HOSTS_MAX_LENGTH) {\n\t\tmemcpy(line, fixed_hosts[*i], strlen(fixed_hosts[*i]));\n\t\t(*i)++;\n\t\treturn line;\n\t}\n\treturn NULL;\n}\n");
        allocator.free(output);
        output = next;
    }

    if (std.mem.eql(u8, relative_path, "src/network/lookup_name.c")) {
        const next = try replaceBytes(allocator, output, "static inline int get_hosts_str(char *line, int length, FILE *f, int *i)\n{\n\tif (f) {\n\t\tchar *ret = fgets(line, length, f);\n\t\tif (ret) {\n\t\t\tsize_t len = strlen(line);\n\t\t\tif (len > 0 && line[len - 1] != '\\n' && len < length - 1) {\n\t\t\t\tline[len] = '\\n';\n\t\t\t\tline[len + 1] = '\\0';\n\t\t\t}\n\t\t}\n\t\treturn ret;\n\t}\n\tif (*i < FIXED_HOSTS_MAX_LENGTH) {\n\t\tmemcpy(line, fixed_hosts[*i], strlen(fixed_hosts[*i]));\n\t\t(*i)++;\n\t\treturn 1;\n\t}\n\treturn NULL;\n}\n", "static inline char *get_hosts_str(char *line, int length, FILE *f, int *i)\n{\n\tif (f) {\n\t\tchar *ret = fgets(line, length, f);\n\t\tif (ret) {\n\t\t\tsize_t len = strlen(line);\n\t\t\tif (len > 0 && line[len - 1] != '\\n' && len < length - 1) {\n\t\t\t\tline[len] = '\\n';\n\t\t\t\tline[len + 1] = '\\0';\n\t\t\t}\n\t\t}\n\t\treturn ret;\n\t}\n\tif (*i < FIXED_HOSTS_MAX_LENGTH) {\n\t\tmemcpy(line, fixed_hosts[*i], strlen(fixed_hosts[*i]));\n\t\t(*i)++;\n\t\treturn line;\n\t}\n\treturn NULL;\n}\n");
        allocator.free(output);
        output = next;
    }

    if (std.mem.eql(u8, relative_path, "src/network/getaddrinfo.c")) {
        const next = try replaceBytes(allocator, output, "g_recursiveKey = NULL;", "g_recursiveKey = 0;");
        allocator.free(output);
        output = next;
    }

    return output;
}

const ohos_fortify_libc_s_stubs =
    \\
    \\/* OpenHarmony musl adds runtime fortify check functions (enabled via _FORTIFY_SOURCE).
    \\   The link-time stub must export them so executables can be linked as dynamic-PIC. */
    \\.globl __fd_chk
    \\.type __fd_chk, %function;
    \\__fd_chk:
    \\.globl __open_chk
    \\.type __open_chk, %function;
    \\__open_chk:
    \\.globl __openat_chk
    \\.type __openat_chk, %function;
    \\__openat_chk:
    \\.globl __open64_chk
    \\.type __open64_chk, %function;
    \\__open64_chk:
    \\.globl __openat64_chk
    \\.type __openat64_chk, %function;
    \\__openat64_chk:
    \\.globl __poll_chk
    \\.type __poll_chk, %function;
    \\__poll_chk:
    \\.globl __ppoll_chk
    \\.type __ppoll_chk, %function;
    \\__ppoll_chk:
    \\.globl __recvfrom_chk
    \\.type __recvfrom_chk, %function;
    \\__recvfrom_chk:
    \\.globl __sendto_chk
    \\.type __sendto_chk, %function;
    \\__sendto_chk:
    \\.globl __recv_chk
    \\.type __recv_chk, %function;
    \\__recv_chk:
    \\.globl __send_chk
    \\.type __send_chk, %function;
    \\__send_chk:
    \\.globl __umask_chk
    \\.type __umask_chk, %function;
    \\__umask_chk:
    \\.globl __strlen_chk
    \\.type __strlen_chk, %function;
    \\__strlen_chk:
    \\.globl __strncat_chk
    \\.type __strncat_chk, %function;
    \\__strncat_chk:
    \\.globl __strcat_chk
    \\.type __strcat_chk, %function;
    \\__strcat_chk:
    \\.globl __strcpy_chk
    \\.type __strcpy_chk, %function;
    \\__strcpy_chk:
    \\.globl __memmove_chk
    \\.type __memmove_chk, %function;
    \\__memmove_chk:
    \\.globl __memcpy_chk
    \\.type __memcpy_chk, %function;
    \\__memcpy_chk:
    \\.globl __mempcpy_chk
    \\.type __mempcpy_chk, %function;
    \\__mempcpy_chk:
    \\.globl __stpcpy_chk
    \\.type __stpcpy_chk, %function;
    \\__stpcpy_chk:
    \\.globl __memchr_chk
    \\.type __memchr_chk, %function;
    \\__memchr_chk:
    \\.globl __stpncpy_chk
    \\.type __stpncpy_chk, %function;
    \\__stpncpy_chk:
    \\.globl __strncpy_chk
    \\.type __strncpy_chk, %function;
    \\__strncpy_chk:
    \\.globl __memset_chk
    \\.type __memset_chk, %function;
    \\__memset_chk:
    \\.globl __strlcpy_chk
    \\.type __strlcpy_chk, %function;
    \\__strlcpy_chk:
    \\.globl __strlcat_chk
    \\.type __strlcat_chk, %function;
    \\__strlcat_chk:
    \\.globl __strchr_chk
    \\.type __strchr_chk, %function;
    \\__strchr_chk:
    \\.globl __strrchr_chk
    \\.type __strrchr_chk, %function;
    \\__strrchr_chk:
    \\.globl __memrchr_chk
    \\.type __memrchr_chk, %function;
    \\__memrchr_chk:
    \\.globl __getcwd_chk
    \\.type __getcwd_chk, %function;
    \\__getcwd_chk:
    \\.globl __pread_chk
    \\.type __pread_chk, %function;
    \\__pread_chk:
    \\.globl __pwrite_chk
    \\.type __pwrite_chk, %function;
    \\__pwrite_chk:
    \\.globl __read_chk
    \\.type __read_chk, %function;
    \\__read_chk:
    \\.globl __write_chk
    \\.type __write_chk, %function;
    \\__write_chk:
    \\.globl __readlink_chk
    \\.type __readlink_chk, %function;
    \\__readlink_chk:
    \\.globl __readlinkat_chk
    \\.type __readlinkat_chk, %function;
    \\__readlinkat_chk:
    \\.globl __fread_chk
    \\.type __fread_chk, %function;
    \\__fread_chk:
    \\.globl __fwrite_chk
    \\.type __fwrite_chk, %function;
    \\__fwrite_chk:
    \\.globl __fgets_chk
    \\.type __fgets_chk, %function;
    \\__fgets_chk:
    \\.globl __vsnprintf_chk
    \\.type __vsnprintf_chk, %function;
    \\__vsnprintf_chk:
    \\.globl __vsprintf_chk
    \\.type __vsprintf_chk, %function;
    \\__vsprintf_chk:
    \\.globl __snprintf_chk
    \\.type __snprintf_chk, %function;
    \\__snprintf_chk:
    \\.globl __sprintf_chk
    \\.type __sprintf_chk, %function;
    \\__sprintf_chk:
    \\
;

fn injectOhosLibcSStubs(allocator: std.mem.Allocator, input: []const u8) !?[]u8 {
    // Keep generation idempotent, and avoid changing the generic musl stub.
    if (std.mem.indexOf(u8, input, "__fd_chk:") != null) return null;

    const insertion_index = if (std.mem.indexOf(u8, input, "\n__assert_fail:\n")) |idx|
        idx + "\n__assert_fail:\n".len
    else if (std.mem.indexOf(u8, input, "\n.text\n")) |idx|
        idx + "\n.text\n".len
    else
        return error.OhosLibcSInsertionPointNotFound;

    const out = try allocator.alloc(u8, input.len + ohos_fortify_libc_s_stubs.len);
    @memcpy(out[0..insertion_index], input[0..insertion_index]);
    @memcpy(out[insertion_index .. insertion_index + ohos_fortify_libc_s_stubs.len], ohos_fortify_libc_s_stubs);
    @memcpy(out[insertion_index + ohos_fortify_libc_s_stubs.len ..], input[insertion_index..]);
    return out;
}

fn fileExists(io: Io, path: []const u8) bool {
    Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn dirExists(io: Io, path: []const u8) bool {
    var dir = Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    defer dir.close(io);
    return true;
}

fn shouldAlwaysCopy(relative_path: []const u8) bool {
    if (!std.mem.startsWith(u8, relative_path, "arch/") and !std.mem.startsWith(u8, relative_path, "include/") and !std.mem.startsWith(u8, relative_path, "src/") and !std.mem.startsWith(u8, relative_path, "ldso/") and !std.mem.startsWith(u8, relative_path, "compat/time32/")) {
        return false;
    }

    const ext = std.fs.path.extension(relative_path);
    return !std.mem.eql(u8, ext, ".c") and
        !std.mem.eql(u8, ext, ".s") and
        !std.mem.eql(u8, ext, ".S");
}

fn isMuslArchComponent(component: []const u8) bool {
    const musl_arch_names = [_][]const u8{
        "aarch64",
        "arm",
        "generic",
        "hexagon",
        "i386",
        "loongarch64",
        "m68k",
        "microblaze",
        "mips",
        "mips64",
        "mipsn32",
        "or1k",
        "powerpc",
        "powerpc64",
        "riscv32",
        "riscv64",
        "s390x",
        "sh",
        "x32",
        "x86_64",
    };
    for (musl_arch_names) |musl_arch_name| {
        if (std.mem.eql(u8, musl_arch_name, component)) return true;
    }
    return false;
}

fn isKeptOhosArchComponent(component: []const u8) bool {
    return std.mem.eql(u8, component, "generic") or
        std.mem.eql(u8, component, "aarch64") or
        std.mem.eql(u8, component, "arm") or
        std.mem.eql(u8, component, "x86_64");
}

fn shouldKeepGeneratedRelativePath(relative_path: []const u8) bool {
    var components = std.mem.splitScalar(u8, relative_path, '/');
    while (components.next()) |component| {
        if (component.len == 0) continue;
        if (std.mem.eql(u8, component, "liteos_a")) return false;
        if (isMuslArchComponent(component) and !isKeptOhosArchComponent(component)) return false;
    }
    return true;
}

fn copyIfDifferent(
    allocator: std.mem.Allocator,
    io: Io,
    source_base_path: []const u8,
    generic_musl_path: []const u8,
    out_dir: []const u8,
    relative_path: []const u8,
    stats: *Stats,
) !void {
    stats.scanned += 1;

    const ohos_file_path = try std.fs.path.join(allocator, &[_][]const u8{ source_base_path, relative_path });
    defer allocator.free(ohos_file_path);

    const max_size = 2 * 1024 * 1024 * 1024;
    const raw_ohos = try Io.Dir.cwd().readFileAlloc(io, ohos_file_path, allocator, .limited(max_size));
    defer allocator.free(raw_ohos);
    const normalized_ohos = try normalizeContent(allocator, raw_ohos);
    defer allocator.free(normalized_ohos);
    const fixed_ohos = try applyFixups(allocator, relative_path, normalized_ohos);
    defer allocator.free(fixed_ohos);

    const musl_file_path = try std.fs.path.join(allocator, &[_][]const u8{ generic_musl_path, relative_path });
    defer allocator.free(musl_file_path);

    if (fileExists(io, musl_file_path)) {
        const raw_musl = try Io.Dir.cwd().readFileAlloc(io, musl_file_path, allocator, .limited(max_size));
        defer allocator.free(raw_musl);
        const normalized_musl = try normalizeContent(allocator, raw_musl);
        defer allocator.free(normalized_musl);
        if (std.mem.eql(u8, fixed_ohos, normalized_musl)) {
            stats.same_as_musl += 1;
            // Keep non-source companion files even when identical so the OHOS
            // overlay directory remains structurally complete.
            if (!shouldAlwaysCopy(relative_path)) return;
        }
    }

    const out_file_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, relative_path });
    defer allocator.free(out_file_path);
    try Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(out_file_path).?);
    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = out_file_path,
        .data = fixed_ohos,
    });
    stats.copied += 1;
}

fn copyIfDifferentMapped(
    allocator: std.mem.Allocator,
    io: Io,
    source_base_path: []const u8,
    source_relative_path: []const u8,
    generic_musl_path: []const u8,
    out_dir: []const u8,
    out_relative_path: []const u8,
    stats: *Stats,
) !void {
    stats.scanned += 1;

    const source_file_path = try std.fs.path.join(allocator, &[_][]const u8{ source_base_path, source_relative_path });
    defer allocator.free(source_file_path);

    const max_size = 2 * 1024 * 1024 * 1024;
    const raw_source = try Io.Dir.cwd().readFileAlloc(io, source_file_path, allocator, .limited(max_size));
    defer allocator.free(raw_source);
    const normalized_source = try normalizeContent(allocator, raw_source);
    defer allocator.free(normalized_source);
    const fixed_source = try applyFixups(allocator, out_relative_path, normalized_source);
    defer allocator.free(fixed_source);

    const musl_file_path = try std.fs.path.join(allocator, &[_][]const u8{ generic_musl_path, out_relative_path });
    defer allocator.free(musl_file_path);

    if (fileExists(io, musl_file_path)) {
        const raw_musl = try Io.Dir.cwd().readFileAlloc(io, musl_file_path, allocator, .limited(max_size));
        defer allocator.free(raw_musl);
        const normalized_musl = try normalizeContent(allocator, raw_musl);
        defer allocator.free(normalized_musl);
        if (std.mem.eql(u8, fixed_source, normalized_musl)) {
            stats.same_as_musl += 1;
            if (!shouldAlwaysCopy(out_relative_path)) return;
        }
    }

    const out_file_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, out_relative_path });
    defer allocator.free(out_file_path);
    try Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(out_file_path).?);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = out_file_path, .data = fixed_source });
    stats.copied += 1;
}

fn writeMirroredFiles(
    allocator: std.mem.Allocator,
    io: Io,
    generic_musl_path: []const u8,
    out_dir: []const u8,
    stats: *Stats,
) !void {
    for (mirrored_files) |mirrored_file| {
        const source_path = try std.fs.path.join(allocator, &[_][]const u8{ generic_musl_path, mirrored_file.source_relative_path });
        defer allocator.free(source_path);

        const max_size = 2 * 1024 * 1024 * 1024;
        const raw = try Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(max_size));
        defer allocator.free(raw);
        const normalized = try normalizeContent(allocator, raw);
        defer allocator.free(normalized);

        const injected = if (std.mem.eql(u8, mirrored_file.relative_path, "libc.S"))
            try injectOhosLibcSStubs(allocator, normalized)
        else
            null;
        defer if (injected) |buf| allocator.free(buf);

        const out_file_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, mirrored_file.relative_path });
        defer allocator.free(out_file_path);
        try Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(out_file_path).?);
        try Io.Dir.cwd().writeFile(io, .{
            .sub_path = out_file_path,
            .data = injected orelse normalized,
        });
        stats.copied += 1;
    }
}

fn copyRootTree(
    allocator: std.mem.Allocator,
    io: Io,
    source_base_path: []const u8,
    out_dir: []const u8,
    root: []const u8,
    stats: ?*Stats,
) !bool {
    const root_abs_path = try std.fs.path.join(allocator, &[_][]const u8{ source_base_path, root });
    defer allocator.free(root_abs_path);
    if (!dirExists(io, root_abs_path)) return false;

    var root_dir = try Io.Dir.cwd().openDir(io, root_abs_path, .{ .iterate = true });
    defer root_dir.close(io);

    var walker = try root_dir.walk(allocator);
    defer walker.deinit();

    var copied_any = false;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const relative_path = try std.fs.path.join(allocator, &[_][]const u8{ root, entry.path });
        defer allocator.free(relative_path);

        const source_file_path = try std.fs.path.join(allocator, &[_][]const u8{ source_base_path, relative_path });
        defer allocator.free(source_file_path);

        const max_size = 2 * 1024 * 1024 * 1024;
        const raw = try Io.Dir.cwd().readFileAlloc(io, source_file_path, allocator, .limited(max_size));
        defer allocator.free(raw);
        const normalized = try normalizeContent(allocator, raw);
        defer allocator.free(normalized);
        const fixed = try applyFixups(allocator, relative_path, normalized);
        defer allocator.free(fixed);

        const out_file_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, relative_path });
        defer allocator.free(out_file_path);
        try Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(out_file_path).?);
        try Io.Dir.cwd().writeFile(io, .{
            .sub_path = out_file_path,
            .data = fixed,
        });

        copied_any = true;
        if (stats) |s| s.copied += 1;
    }

    return copied_any;
}

fn snapshotSupplementalRoots(
    allocator: std.mem.Allocator,
    io: Io,
    source_base_path: []const u8,
    snapshot_dir: []const u8,
) !bool {
    if (dirExists(io, snapshot_dir)) {
        try Io.Dir.cwd().deleteTree(io, snapshot_dir);
    }
    try Io.Dir.cwd().createDirPath(io, snapshot_dir);

    var copied_any = false;
    for (supplemental_roots) |root| {
        copied_any = (try copyRootTree(
            allocator,
            io,
            source_base_path,
            snapshot_dir,
            root,
            null,
        )) or copied_any;
    }
    return copied_any;
}

fn writeSupplementalRoots(
    allocator: std.mem.Allocator,
    io: Io,
    source_base_path: []const u8,
    out_dir: []const u8,
    stats: *Stats,
) !void {
    for (supplemental_roots) |root| {
        _ = try copyRootTree(
            allocator,
            io,
            source_base_path,
            out_dir,
            root,
            stats,
        );
    }
}

fn writeGeneratedFiles(
    allocator: std.mem.Allocator,
    io: Io,
    source_base_path: []const u8,
    ported_source_base_path: ?[]const u8,
    out_dir: []const u8,
    stats: *Stats,
) !void {
    for (generated_files) |generated_file| {
        const source_path = try std.fs.path.join(allocator, &[_][]const u8{ source_base_path, generated_file.relative_path });
        defer allocator.free(source_path);
        if (fileExists(io, source_path)) continue;

        if (ported_source_base_path) |ported_path| {
            const ported_source_path = try std.fs.path.join(allocator, &[_][]const u8{ ported_path, generated_file.relative_path });
            defer allocator.free(ported_source_path);
            if (fileExists(io, ported_source_path)) continue;
        }

        const out_file_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, generated_file.relative_path });
        defer allocator.free(out_file_path);
        try Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(out_file_path).?);
        try Io.Dir.cwd().writeFile(io, .{
            .sub_path = out_file_path,
            .data = generated_file.contents,
        });
        stats.copied += 1;
    }
}

fn processRoot(
    allocator: std.mem.Allocator,
    io: Io,
    source_base_path: []const u8,
    skip_if_exists_in_path: ?[]const u8,
    generic_musl_path: []const u8,
    out_dir: []const u8,
    root: []const u8,
    stats: *Stats,
) !void {
    const root_abs_path = try std.fs.path.join(allocator, &[_][]const u8{ source_base_path, root });
    defer allocator.free(root_abs_path);
    if (!dirExists(io, root_abs_path)) return;

    var root_dir = try Io.Dir.cwd().openDir(io, root_abs_path, .{ .iterate = true });
    defer root_dir.close(io);

    var walker = try root_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const relative_path = try std.fs.path.join(allocator, &[_][]const u8{ root, entry.path });
        defer allocator.free(relative_path);
        if (!shouldKeepGeneratedRelativePath(relative_path)) continue;

        if (skip_if_exists_in_path) |skip_base_path| {
            const skip_candidate_path = try std.fs.path.join(allocator, &[_][]const u8{ skip_base_path, relative_path });
            defer allocator.free(skip_candidate_path);
            if (fileExists(io, skip_candidate_path)) continue;
        }

        try copyIfDifferent(
            allocator,
            io,
            source_base_path,
            generic_musl_path,
            out_dir,
            relative_path,
            stats,
        );
    }
}

fn processOverlayRoot(
    allocator: std.mem.Allocator,
    io: Io,
    source_base_path: []const u8,
    generic_musl_path: []const u8,
    out_dir: []const u8,
    overlay: OverlayDir,
    stats: *Stats,
) !void {
    const root_abs_path = try std.fs.path.join(allocator, &[_][]const u8{ source_base_path, overlay.source_path });
    defer allocator.free(root_abs_path);
    if (!dirExists(io, root_abs_path)) return;

    var root_dir = try Io.Dir.cwd().openDir(io, root_abs_path, .{ .iterate = true });
    defer root_dir.close(io);

    var walker = try root_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const source_relative_path = try std.fs.path.join(allocator, &[_][]const u8{ overlay.source_path, entry.path });
        defer allocator.free(source_relative_path);
        if (!shouldKeepGeneratedRelativePath(source_relative_path)) continue;

        const out_relative_path = if (overlay.dest_path.len == 0)
            try allocator.dupe(u8, entry.path)
        else
            try std.fs.path.join(allocator, &[_][]const u8{ overlay.dest_path, entry.path });
        defer allocator.free(out_relative_path);
        if (!shouldKeepGeneratedRelativePath(out_relative_path)) continue;

        try copyIfDifferentMapped(
            allocator,
            io,
            source_base_path,
            source_relative_path,
            generic_musl_path,
            out_dir,
            out_relative_path,
            stats,
        );
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(allocator);

    var opt_ohos_musl_path: ?[]const u8 = null;
    var opt_generic_musl_path: ?[]const u8 = null;
    var opt_out_dir: ?[]const u8 = null;

    var arg_i: usize = 1;
    while (arg_i < args.len) : (arg_i += 1) {
        if (std.mem.eql(u8, args[arg_i], "--help")) usageAndExit(args[0]);
        if (arg_i + 1 >= args.len) usageAndExit(args[0]);

        if (std.mem.eql(u8, args[arg_i], "--ohos-musl-path")) {
            assert(opt_ohos_musl_path == null);
            opt_ohos_musl_path = args[arg_i + 1];
        } else if (std.mem.eql(u8, args[arg_i], "--generic-musl-path")) {
            assert(opt_generic_musl_path == null);
            opt_generic_musl_path = args[arg_i + 1];
        } else if (std.mem.eql(u8, args[arg_i], "--out")) {
            assert(opt_out_dir == null);
            opt_out_dir = args[arg_i + 1];
        } else {
            usageAndExit(args[0]);
        }

        arg_i += 1;
    }

    const ohos_musl_path = opt_ohos_musl_path orelse usageAndExit(args[0]);
    const generic_musl_path = opt_generic_musl_path orelse usageAndExit(args[0]);
    const out_dir = opt_out_dir orelse usageAndExit(args[0]);
    const opt_ported_ohos_overlay_path = if (dirExists(io, default_ported_ohos_overlay_path))
        default_ported_ohos_overlay_path
    else
        null;

    if (!dirExists(io, ohos_musl_path) or !dirExists(io, generic_musl_path)) {
        std.debug.print("input path not found\n", .{});
        std.process.exit(1);
    }

    var opt_supplemental_snapshot_dir: ?[]const u8 = null;
    if (opt_ported_ohos_overlay_path) |ported_ohos_overlay_path| {
        const snapshot_dir = try std.fmt.allocPrint(allocator, "{s}.ported-snapshot", .{out_dir});
        const copied_any = try snapshotSupplementalRoots(
            allocator,
            io,
            ported_ohos_overlay_path,
            snapshot_dir,
        );
        if (copied_any) {
            opt_supplemental_snapshot_dir = snapshot_dir;
        } else if (dirExists(io, snapshot_dir)) {
            try Io.Dir.cwd().deleteTree(io, snapshot_dir);
        }
    }
    defer if (opt_supplemental_snapshot_dir) |snapshot_dir| {
        Io.Dir.cwd().deleteTree(io, snapshot_dir) catch {};
    };

    if (dirExists(io, out_dir)) {
        // This tool produces a complete overlay tree. Recreate the output
        // directory to avoid stale files from previous runs.
        try Io.Dir.cwd().deleteTree(io, out_dir);
    }
    try Io.Dir.cwd().createDirPath(io, out_dir);

    var stats = Stats{};
    // Stage 1: copy the straightforward OHOS musl roots.
    for (sync_roots) |root| {
        try processRoot(
            allocator,
            io,
            ohos_musl_path,
            null,
            generic_musl_path,
            out_dir,
            root,
            &stats,
        );
    }

    // Stage 2: flatten OHOS linux-specific overlay directories onto the
    // canonical musl destination paths expected by Zig's libc builder.
    for (linux_overlay_dirs) |overlay| {
        try processOverlayRoot(
            allocator,
            io,
            ohos_musl_path,
            generic_musl_path,
            out_dir,
            overlay,
            &stats,
        );
    }

    // Stage 3: synthesize files that do not exist upstream, then mirror
    // generic musl files that OHOS still needs but does not carry itself.
    try writeGeneratedFiles(allocator, io, ohos_musl_path, opt_supplemental_snapshot_dir, out_dir, &stats);
    try writeMirroredFiles(allocator, io, generic_musl_path, out_dir, &stats);

    // Stage 4: copy repo-maintained supplemental roots that are outside the
    // upstream OHOS musl tree, such as x86_64 OpenLibm long-double sources.
    if (opt_supplemental_snapshot_dir) |snapshot_dir| {
        try writeSupplementalRoots(allocator, io, snapshot_dir, out_dir, &stats);
    }

    std.debug.print(
        "scanned={d} copied={d} same_as_musl={d}\n",
        .{ stats.scanned, stats.copied, stats.same_as_musl },
    );
}

fn usageAndExit(arg0: []const u8) noreturn {
    std.debug.print(
        "Usage: {s} --ohos-musl-path <dir> --generic-musl-path <dir> --out <dir>\n",
        .{arg0},
    );
    std.process.exit(1);
}
