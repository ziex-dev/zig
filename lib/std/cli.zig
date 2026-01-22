const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const fmt = std.fmt;
const Allocator = mem.Allocator;
const Args = std.process.Args;
const EnumSet = std.EnumSet;

pub const Error = error{ MissingValue, InvalidValue, UnknownFlag };

pub const Config = struct {
    pub const sorted: @This() = .{ .sort = true };
    pub const default: @This() = .{ .sort = false };

    sort: bool = false,
};

pub fn parse(
    comptime T: type,
    comptime config: Config,
    args: if (config.sort) [][:0]const u8 else []const [:0]const u8,
    allocator: Allocator,
) (Error || Allocator.Error)!T {
    if (config.sort and args.len > 1) partition(args[1..]);
    var iter: Iterator = .{ .args = args };
    return parseInner(T, &iter, allocator);
}

// This indirection is just to enable selective dropping of the first
// arg (program name, subcommand, etc.)
inline fn parseInner(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    iter.skip() orelse return Error.MissingValue;
    return parseValue(T, iter, allocator);
}

fn parseValue(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    return switch (@typeInfo(T)) {
        .void => {},
        .bool => parseBool(T, iter),
        .int, .float => parseScalar(T, iter),
        .@"enum" => parseEnum(T, iter),
        .array => parseArray(T, iter, allocator),
        .@"struct" => |s| if (s.is_tuple)
            parseTuple(T, iter, allocator)
        else
            parseStruct(T, iter, allocator),
        .@"union" => parseUnion(T, iter, allocator),
        .vector => parseVector(T, iter, allocator),
        .optional => parseOptional(T, iter, allocator),
        .pointer => parsePointer(T, iter, allocator),
        else => @compileError("Unsupported type:" ++ @typeName(T)),
    };
}

// @"struct" rules:
// struct { foo: u32, bar: bool }, expect args like --foo 42 --bar 1
// field types can be void (presence-only flag), optional, or have default values
// fields without default values or optional types are required
fn parseStruct(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const info = @typeInfo(T);
    const fields = info.@"struct".fields;
    var result: T = undefined;

    // First pass for setting defaults
    inline for (fields) |field| @field(result, field.name) = field.defaultValue() orelse
        if (@typeInfo(field.type) == .optional) null else continue;

    const FieldEnum = meta.FieldEnum(T);
    var fieldsSeen = EnumSet(FieldEnum).initEmpty();

    // Parse args - stop on first non-flag (positional)
    while (iter.peek()) |arg| {
        const field_name = flagName(arg) orelse break;
        _ = iter.skip();

        inline for (fields) |field| {
            if (mem.eql(u8, field.name, field_name)) {
                fieldsSeen.insert(@field(FieldEnum, field.name));
                @field(result, field.name) = try parseValue(field.type, iter, allocator);
                break;
            }
        } else {
            return Error.UnknownFlag;
        }
    }

    // Required fields were set?
    inline for (fields) |field|
        if (field.default_value_ptr == null and
            !(@typeInfo(field.type) == .optional) and
            !fieldsSeen.contains(@field(FieldEnum, field.name)))
            return Error.MissingValue;

    return result;
}

fn parseTuple(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const fields = @typeInfo(T).@"struct".fields;
    var result: T = undefined;
    inline for (fields) |field| {
        @field(result, field.name) = try parseValue(field.type, iter, allocator);
    }
    return result;
}

fn parseUnion(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const info = @typeInfo(T).@"union";
    const Tag = info.tag_type orelse @compileError("Non-tagged unions are not supported");
    const arg = iter.peek() orelse return Error.MissingValue;
    const tag = meta.stringToEnum(Tag, arg) orelse return Error.InvalidValue;

    inline for (info.fields) |field| if (@field(Tag, field.name) == tag) {
        const value = try parseInner(field.type, iter, allocator);
        return @unionInit(T, field.name, value);
    };

    unreachable;
}

fn parseEnum(comptime T: type, iter: *Iterator) Error!T {
    const arg = iter.peek() orelse return Error.MissingValue;
    const val = meta.stringToEnum(T, arg) orelse return Error.InvalidValue;
    _ = iter.skip();
    return val;
}

fn parseScalar(comptime T: type, iter: *Iterator) Error!T {
    const arg = iter.peek() orelse return Error.MissingValue;
    const val = switch (@typeInfo(T)) {
        .int => fmt.parseInt(T, arg, 0) catch return Error.InvalidValue,
        .float => fmt.parseFloat(T, arg) catch return Error.InvalidValue,
        else => unreachable,
    };
    _ = iter.skip();
    return val;
}

fn parsePointer(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const info = @typeInfo(T).pointer;

    return switch (info.size) {
        .one => one: {
            const ptr = try allocator.create(info.child);
            ptr.* = try parseValue(info.child, iter, allocator);
            break :one ptr;
        },
        .slice, .c, .many => slice: {
            if (info.child == u8) {
                const arg = iter.peek() orelse return Error.MissingValue;
                _ = iter.skip();
                const duped = try allocator.dupe(u8, arg);
                break :slice if (info.size == .many) duped.ptr else duped;
            }
            var list: std.ArrayList(info.child) = .empty;
            while (parseValue(info.child, iter, allocator)) |val| {
                try list.append(allocator, val);
            } else |_| {}
            const slice = try list.toOwnedSlice(allocator);
            break :slice if (info.size == .many) slice.ptr else slice;
        },
    };
}

fn parseArray(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const info = @typeInfo(T).array;
    var result: T = undefined;
    inline for (0..info.len) |i| result[i] =
        try parseValue(info.child, iter, allocator);
    return result;
}

fn parseVector(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const info = @typeInfo(T).vector;
    var result: T = undefined;
    inline for (0..info.len) |i| result[i] =
        try parseValue(info.child, iter, allocator);
    return result;
}

// bool rules:
// maps {1/0, true/false, yes/no and on/off} to bool
// NOTE: bool expects a value. For presence-only flags, use ?void type in struct
fn parseBool(comptime T: type, iter: *Iterator) Error!T {
    const arg = iter.peek() orelse return Error.MissingValue;

    if (mem.eql(u8, arg, "1") or
        mem.eql(u8, arg, "true") or
        mem.eql(u8, arg, "yes") or
        mem.eql(u8, arg, "on"))
    {
        _ = iter.skip();
        return true;
    }

    if (mem.eql(u8, arg, "0") or
        mem.eql(u8, arg, "false") or
        mem.eql(u8, arg, "no") or
        mem.eql(u8, arg, "off"))
    {
        _ = iter.skip();
        return false;
    }

    return Error.InvalidValue;
}

fn parseOptional(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const ChildT = @typeInfo(T).optional.child;

    return parseValue(ChildT, iter, allocator) catch |err| switch (err) {
        Error.MissingValue => null,
        else => err,
    };
}

// If arg is a flag, return its name without the prefix, otherwise return null
inline fn flagName(arg: []const u8) ?[]const u8 {
    if (mem.startsWith(u8, arg, "--")) return arg[2..];

    if (mem.startsWith(u8, arg, "-") or
        mem.startsWith(u8, arg, "/") or
        mem.startsWith(u8, arg, "+")) return arg[1..];

    return null;
}

// Stable in-place partition: moves all flag units before positionals
fn partition(args: [][:0]const u8) void {
    var write: usize = 0;
    var read: usize = 0;

    while (read < args.len) {
        if (flagName(args[read]) != null) {
            const has_value = mem.indexOfScalar(u8, args[read], '=') == null and
                read + 1 < args.len and flagName(args[read + 1]) == null;
            const unit_size = @as(usize, @intFromBool(has_value)) + 1;

            mem.rotate([:0]const u8, args[write .. read + unit_size], read - write);
            write += unit_size;
            read += unit_size;
        } else read += 1;
    }
}

// This iterates over all "tokens" in the args array which can be in the next
// index position or in the same index position separated by '=', serving a rather
// different purpose than std.process.Args.Iterator
const Iterator = struct {
    args: []const [:0]const u8,
    index: usize = 0,
    @"=": ?[:0]const u8 = null, // stores value after '=' to return on next call

    pub fn init(args: []const [:0]const u8) Iterator {
        return .{ .args = args };
    }

    pub fn next(self: *Iterator) ?[]const u8 {
        if (self.@"=") |value| {
            self.@"=" = null;
            return value;
        }

        if (self.index >= self.args.len) return null;

        const arg = self.args[self.index];
        self.index += 1;

        if (flagName(arg)) |_| if (mem.findScalar(u8, arg, '=')) |eq_pos| {
            self.@"=" = arg[eq_pos + 1 .. :0];
            return arg[0..eq_pos];
        };

        return arg;
    }

    pub fn peek(self: *Iterator) ?[]const u8 {
        const prev = .{ self.index, self.@"=" };
        defer {
            self.index = prev[0];
            self.@"=" = prev[1];
        }

        return self.next();
    }

    pub fn skip(self: *Iterator) ?void {
        _ = self.next() orelse return null;
    }
};

test "std.cli: Iterator" {
    var iter1: Iterator = .{ .args = &.{ "--foo", "42", "--bar", "1" } };
    try testing.expectEqualStrings("--foo", iter1.next().?);
    try testing.expectEqualStrings("42", iter1.next().?);
    try testing.expectEqualStrings("--bar", iter1.next().?);
    try testing.expectEqualStrings("1", iter1.next().?);
    try testing.expectEqual(null, iter1.next());

    var iter2: Iterator = .{ .args = &.{ "--foo=42", "--bar=hello" } };
    try testing.expectEqualStrings("--foo", iter2.next().?);
    try testing.expectEqualStrings("42", iter2.next().?);
    try testing.expectEqualStrings("--bar", iter2.next().?);
    try testing.expectEqualStrings("hello", iter2.next().?);
    try testing.expectEqual(null, iter2.next());
}

test "std.cli: partition" {
    // Positionals appear BEFORE flags - partition reorders them
    var args = [_][:0]const u8{ "file1.txt", "file2.txt", "--verbose", "true", "--output", "result.txt" };
    partition(&args);

    try testing.expectEqualStrings("--verbose", args[0]);
    try testing.expectEqualStrings("true", args[1]);
    try testing.expectEqualStrings("--output", args[2]);
    try testing.expectEqualStrings("result.txt", args[3]);
    try testing.expectEqualStrings("file1.txt", args[4]);
    try testing.expectEqualStrings("file2.txt", args[5]);
}

// zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux -j8
test "std.cli: zig build" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const Optimize = enum { Debug, ReleaseSafe, ReleaseFast, ReleaseSmall };
    const BuildOptions = struct {
        optimize: Optimize = .Debug,
        target: []const u8 = "native",
        j: u32 = 1,
        verbose: bool = false,
    };

    const parsed = try parse(BuildOptions, .default, &.{
        "zig-build", "--optimize=ReleaseFast", "--target=x86_64-linux", "-j=8",
    }, arena.allocator());

    try testing.expectEqual(.ReleaseFast, parsed.optimize);
    try testing.expectEqualStrings("x86_64-linux", parsed.target);
    try testing.expectEqual(@as(u32, 8), parsed.j);
    try testing.expectEqual(false, parsed.verbose);
}

// git clone --depth 1 --branch main https://github.com/ziglang/zig
// git commit --message "fix: resolve memory leak" --amend true
// git log --oneline true --count 10
test "std.cli: git" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Command = union(enum) {
        clone: struct {
            depth: ?u32 = null,
            branch: []const u8 = "master",
            url: []const u8,
        },
        commit: struct {
            message: []const u8,
            amend: bool = false,
            signoff: bool = false,
        },
        log: struct {
            oneline: bool = false,
            count: u32 = 20,
        },
    };

    const clone = try parse(Command, .default, &.{
        "git", "clone", "--depth", "1", "--branch", "main", "--url", "https://github.com/ziglang/zig",
    }, allocator);
    try testing.expectEqual(@as(?u32, 1), clone.clone.depth);
    try testing.expectEqualStrings("main", clone.clone.branch);
    try testing.expectEqualStrings("https://github.com/ziglang/zig", clone.clone.url);

    const commit = try parse(Command, .default, &.{
        "git", "commit", "--message", "fix: resolve memory leak", "--amend", "true",
    }, allocator);
    try testing.expectEqualStrings("fix: resolve memory leak", commit.commit.message);
    try testing.expectEqual(true, commit.commit.amend);

    const log = try parse(Command, .default, &.{ "git", "log", "--oneline", "true", "--count", "10" }, allocator);
    try testing.expectEqual(true, log.log.oneline);
    try testing.expectEqual(@as(u32, 10), log.log.count);
}

// curl --request POST --header "Content-Type: application/json" --data '{"key":"value"}' https://api.example.com
test "std.cli: curl" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const Method = enum { GET, POST, PUT, DELETE, PATCH };
    const CurlOptions = struct {
        request: Method = .GET,
        header: []const u8 = "",
        data: []const u8 = "",
        output: []const u8 = "-",
        silent: bool = false,
        url: []const u8,
    };

    const parsed = try parse(CurlOptions, .default, &.{
        "curl",                "--request",                      "POST",
        "--header",            "Content-Type: application/json", "--data",
        "{\"key\":\"value\"}", "--url",                          "https://api.example.com/endpoint",
    }, arena.allocator());

    try testing.expectEqual(.POST, parsed.request);
    try testing.expectEqualStrings("Content-Type: application/json", parsed.header);
    try testing.expectEqualStrings("{\"key\":\"value\"}", parsed.data);
    try testing.expectEqualStrings("https://api.example.com/endpoint", parsed.url);
}

// ffmpeg -i input.mp4 --codec h264 --bitrate 4500 --resolution 1920 1080 --fps 60 output.mp4
test "std.cli: ffmpeg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const Codec = enum { h264, h265, vp9, av1 };
    const FfmpegOptions = struct {
        struct {
            i: []const u8,
            codec: Codec = .h264,
            bitrate: u32 = 2500,
            resolution: @Vector(2, u32) = .{ 1280, 720 },
            fps: u8 = 30,
        },
        []const u8, // output file
    };

    const opts, const output = try parse(FfmpegOptions, .default, &.{
        "ffmpeg",    "-i",   "input.mp4",    "--codec", "h265",
        "--bitrate", "4500", "--resolution", "1920",    "1080",
        "--fps",     "60",   "output.mp4",
    }, arena.allocator());

    try testing.expectEqualStrings("input.mp4", opts.i);
    try testing.expectEqual(.h265, opts.codec);
    try testing.expectEqual(@as(u32, 4500), opts.bitrate);
    try testing.expectEqual(@Vector(2, u32){ 1920, 1080 }, opts.resolution);
    try testing.expectEqual(@as(u8, 60), opts.fps);
    try testing.expectEqualStrings("output.mp4", output);
}

// cc -O2 --target x86_64-linux --output program main.c utils.c lib.c
test "std.cli: cc" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const OptLevel = enum { O0, O1, O2, O3, Os, Oz };
    const CompilerOptions = struct {
        struct {
            O: OptLevel = .O0,
            target: []const u8 = "native",
            output: []const u8 = "a.out",
            g: bool = false,
        },
        []const []const u8, // input files
    };

    const opts, const files = try parse(CompilerOptions, .default, &.{
        "cc", "-O", "O2", "--target", "x86_64-linux", "--output", "program", "main.c", "utils.c", "lib.c",
    }, arena.allocator());

    try testing.expectEqual(.O2, opts.O);
    try testing.expectEqualStrings("x86_64-linux", opts.target);
    try testing.expectEqualStrings("program", opts.output);
    try testing.expectEqual(@as(usize, 3), files.len);
    try testing.expectEqualStrings("main.c", files[0]);
    try testing.expectEqualStrings("utils.c", files[1]);
    try testing.expectEqualStrings("lib.c", files[2]);
}

// docker run --detach true --publish 8080 80 --env KEY=value --name myapp nginx:latest
test "std.cli: docker run" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const DockerRun = struct {
        struct {
            detach: bool = false,
            publish: @Vector(2, u16) = .{ 0, 0 },
            env: []const u8 = "",
            name: []const u8 = "",
            volume: []const u8 = "",
        },
        []const u8, // image
    };

    const opts, const image = try parse(DockerRun, .default, &.{
        "docker-run", "--detach", "true", "--publish", "8080", "80", "--env", "KEY=value", "--name", "myapp", "nginx:latest",
    }, arena.allocator());

    try testing.expectEqual(true, opts.detach);
    try testing.expectEqual(@Vector(2, u16){ 8080, 80 }, opts.publish);
    try testing.expectEqualStrings("KEY=value", opts.env);
    try testing.expectEqualStrings("myapp", opts.name);
    try testing.expectEqualStrings("nginx:latest", image);
}

// tar --create true --gzip true --file archive.tar.gz src/ lib/ include/
test "std.cli: tar" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const TarOptions = struct {
        struct {
            create: bool = false,
            extract: bool = false,
            gzip: bool = false,
            verbose: bool = false,
            file: []const u8,
        },
        []const []const u8, // paths
    };

    const opts, const paths = try parse(TarOptions, .default, &.{
        "tar", "--create", "true", "--gzip", "true", "--file", "archive.tar.gz", "src/", "lib/", "include/",
    }, arena.allocator());

    try testing.expectEqual(true, opts.create);
    try testing.expectEqual(true, opts.gzip);
    try testing.expectEqualStrings("archive.tar.gz", opts.file);
    try testing.expectEqual(@as(usize, 3), paths.len);
    try testing.expectEqualStrings("src/", paths[0]);
    try testing.expectEqualStrings("lib/", paths[1]);
    try testing.expectEqualStrings("include/", paths[2]);
}
