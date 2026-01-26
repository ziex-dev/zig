//! Type-driven command-line argument parser.
//!
//! Structs map to named flags, tuples to positionals, unions to subcommands.
//!
//! ```
//! const Args = struct {
//!     struct { verbose: ?void = null, output: ?[]const u8 = null },
//!     []const u8,
//! };
//! const named, const positionals = try std.cli.parse(Args, args, allocator);
//! ```

const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const fmt = std.fmt;
const Allocator = mem.Allocator;
const EnumSet = std.EnumSet;

/// Parsing errors returned by `parse`.
pub const Error = error{
    /// Required argument not provided.
    MissingValue,
    /// Argument couldn't be parsed as expected type.
    InvalidValue,
    /// Flag name not found in struct fields.
    UnknownFlag,
};

/// Parse command-line arguments into type `T`. Skips first arg (program name).
///
/// - `T`: struct for flags, tuple for positionals, union for subcommands
/// - `args`: Argument slice. see `std.process.Args.toSlice`
/// - `allocator`: for string/slice allocations
///
/// Returns parsed `T` or `Error`.
pub fn parse(
    comptime T: type,
    args: [][:0]const u8,
    allocator: Allocator,
) (Error || Allocator.Error)!T {
    var iter: Iterator = .init(args);
    iter.skip() orelse return Error.MissingValue;
    return parseValue(T, &iter, allocator);
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

fn parseStruct(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const fields = @typeInfo(T).@"struct".fields;
    var result: T = undefined;

    iter.partitionRemaining();

    inline for (fields) |f| @field(result, f.name) = f.defaultValue() orelse
        if (@typeInfo(f.type) == .optional) null else continue;

    const FieldEnum = meta.FieldEnum(T);
    var seen = EnumSet(FieldEnum).initEmpty();

    while (iter.peek()) |arg| {
        const name = flagName(arg) orelse break;
        _ = iter.skip();
        inline for (fields) |f| {
            if (mem.eql(u8, f.name, name)) {
                seen.insert(@field(FieldEnum, f.name));
                @field(result, f.name) = try parseValue(f.type, iter, allocator);
                break;
            }
        } else return Error.UnknownFlag;
    }

    if (iter.peek()) |a| {
        if (mem.eql(u8, a, "--")) _ = iter.skip();
    }

    inline for (fields) |f|
        if (f.default_value_ptr == null and @typeInfo(f.type) != .optional and
            !seen.contains(@field(FieldEnum, f.name))) return Error.MissingValue;

    return result;
}

fn parseTuple(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const fields = @typeInfo(T).@"struct".fields;
    var result: T = undefined;

    inline for (fields) |field|
        @field(result, field.name) = try parseValue(field.type, iter, allocator);

    return result;
}

fn parseUnion(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    const info = @typeInfo(T).@"union";
    const Tag = info.tag_type orelse @compileError("Non-tagged unions are not supported");

    const arg = iter.next() orelse
        return Error.MissingValue;

    const tag = meta.stringToEnum(Tag, arg) orelse
        return Error.InvalidValue;

    inline for (info.fields) |field| if (@field(Tag, field.name) == tag)
        return @unionInit(T, field.name, try parseValue(field.type, iter, allocator));

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

// NOTE: bool expects a value. For presence-only flags, use ?void type in struct
fn parseBool(comptime T: type, iter: *Iterator) Error!T {
    const arg = iter.peek() orelse return Error.MissingValue;

    inline for (.{ "1", "true", "yes", "on" }) |s| if (mem.eql(u8, arg, s)) {
        _ = iter.skip();
        return true;
    };

    inline for (.{ "0", "false", "no", "off" }) |s| if (mem.eql(u8, arg, s)) {
        _ = iter.skip();
        return false;
    };

    return Error.InvalidValue;
}

fn parseOptional(comptime T: type, iter: *Iterator, allocator: Allocator) (Error || Allocator.Error)!T {
    return parseValue(@typeInfo(T).optional.child, iter, allocator) catch |err| switch (err) {
        Error.MissingValue => null,
        else => err,
    };
}

inline fn flagName(arg: []const u8) ?[]const u8 {
    if (mem.startsWith(u8, arg, "--")) return if (arg.len == 2) null else arg[2..];

    if (mem.startsWith(u8, arg, "-") or
        mem.startsWith(u8, arg, "+")) return arg[1..];

    return null;
}

// Stable in-place partition: moves all flag units before positionals
// Stops at "--" (everything after is positional)
fn partition(args: [][:0]const u8) void {
    var write: usize = 0;
    var read: usize = 0;

    while (read < args.len) {
        if (mem.eql(u8, args[read], "--")) break;
        if (flagName(args[read])) |_| {
            var end = read + 1;
            if (mem.indexOfScalar(u8, args[read], '=') == null)
                while (end < args.len and flagName(args[end]) == null) : (end += 1) {};
            mem.rotate([:0]const u8, args[write..end], read - write);
            write += end - read;
            read = end;
        } else read += 1;
    }
}

// This iterates over all "tokens" in the args array which can be in the next
// index position or in the same index position separated by '=', serving a rather
// different purpose than std.process.Args.Iterator
const Iterator = struct {
    args: [][:0]const u8,
    index: usize = 0,
    @"=": ?[:0]const u8 = null,

    pub fn init(args: [][:0]const u8) @This() {
        return .{ .args = args };
    }

    pub fn next(this: *@This()) ?[]const u8 {
        if (this.@"=") |v| {
            this.@"=" = null;
            return v;
        }
        if (this.index >= this.args.len) return null;

        const arg = this.args[this.index];
        this.index += 1;

        if (flagName(arg) != null) if (mem.indexOfScalar(u8, arg, '=')) |i| {
            this.@"=" = arg[i + 1 .. :0];
            return arg[0..i];
        };
        return arg;
    }

    pub fn peek(this: *@This()) ?[]const u8 {
        const s = .{ this.index, this.@"=" };
        defer {
            this.index = s[0];
            this.@"=" = s[1];
        }
        return this.next();
    }

    pub fn skip(this: *@This()) ?void {
        _ = this.next() orelse return null;
    }

    pub fn collect(this: *@This(), allocator: Allocator) ![]const []const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        while (this.next()) |arg| try list.append(allocator, arg);
        return list.toOwnedSlice(allocator);
    }

    pub fn partitionRemaining(this: *@This()) void {
        if (this.index < this.args.len) partition(this.args[this.index..]);
    }
};

test "std.cli: Iterator" {
    var args = [_][:0]const u8{ "--foo=42", "--bar", "1", "--foobar=💔", "🥀" };
    const expected: []const []const u8 = &.{ "--foo", "42", "--bar", "1", "--foobar", "💔", "🥀" };

    var it: Iterator = .init(&args);

    const actual = try it.collect(testing.allocator);
    defer testing.allocator.free(actual);

    try testing.expectEqualDeep(expected, actual);
}

test "std.cli: partition" {
    var actual = [_][:0]const u8{ "output.mp4", "--resolution", "1920", "1080", "--fps", "60", "input.mp4" };
    const expected: []const []const u8 = &.{ "--resolution", "1920", "1080", "--fps", "60", "input.mp4", "output.mp4" };

    partition(&actual);
    try testing.expectEqualDeep(expected, &actual);
}

test "std.cli: simple" {
    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const types = .{
        bool,
        i32,
        f64,
        void,
        ?bool,
        ?i32,
        ?f64,
        enum { red, green, blue },
        ?enum { one, many },
    };

    var arguments = [_][2][:0]const u8{
        .{ "<arg0>", "true" },
        .{ "<arg1>", "42" },
        .{ "<arg2>", "3.14" },
        .{ "<arg3>", "" },
        .{ "<arg4>", "false" },
        .{ "<arg5>", "-123" },
        .{ "<arg6>", "2.718" },
        .{ "<arg7>", "green" },
        .{ "<arg8>", "one" },
    };
    const expected = .{
        true,
        42,
        3.14,
        {},
        false,
        @as(?i32, -123),
        @as(?f64, 2.718),
        .green,
        .one,
    };

    inline for (types, &arguments, expected) |T, *a, e|
        try testing.expectEqual(e, try parse(T, a, allocator));
}

test "std.cli: sequences" {
    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const types = .{
        [3]i32,
        @Vector(3, f64),
        struct { i32, bool, f64 },
        []const []const u8,
    };

    var arguments = [_][4][:0]const u8{
        .{ "<arg0>", "1", "2", "3" },
        .{ "<arg0>", "1.5", "2.5", "3.5" },
        .{ "<arg0>", "42", "true", "3.14" },
        .{ "<arg0>", "hello", "🦎", "good" },
    };

    const expected = .{
        [3]i32{ 1, 2, 3 },
        @Vector(3, f64){ 1.5, 2.5, 3.5 },
        .{ 42, true, 3.14 },
        @as([]const []const u8, &.{ "hello", "🦎", "good" }),
    };

    inline for (types, &arguments, expected) |T, *a, e|
        try testing.expectEqualDeep(e, try parse(T, a, allocator));
}

test "std.cli: struct" {
    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const Point = struct { x: i32 = 0, y: i32 = 0 };
    const Config = struct { name: []const u8, verbose: bool = false };
    const Color = struct { r: u8 = 0, g: u8 = 0, b: u8 = 0 };

    const types = .{ Point, Config, Color };

    var arguments = [_][5][:0]const u8{
        .{ "<arg0>", "--x", "10", "--y", "20" },
        .{ "<arg0>", "--verbose", "true", "--name", "alice" },
        .{ "<arg0>", "--r", "255", "--g", "128" },
    };

    const expected = .{
        Point{ .x = 10, .y = 20 },
        Config{ .name = "alice", .verbose = true },
        Color{ .r = 255, .g = 128 },
    };

    inline for (types, &arguments, expected) |T, *a, e|
        try testing.expectEqualDeep(e, try parse(T, a, allocator));
}

test "std.cli: union" {
    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const Op = union(enum) { add: i32, sub: i32, nop: void };

    const types = .{ Op, Op, Op };

    var arguments = [_][3][:0]const u8{
        .{ "<arg0>", "add", "5" },
        .{ "<arg0>", "sub", "-3" },
        .{ "<arg0>", "nop", "" },
    };

    const expected = .{
        Op{ .add = 5 },
        Op{ .sub = -3 },
        Op{ .nop = {} },
    };

    inline for (types, &arguments, expected) |T, *a, e|
        try testing.expectEqualDeep(e, try parse(T, a, allocator));
}

test "std.cli: combined" {
    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const EncodeOptions = struct {
        input: []const u8,
        output: []const u8,
        format: enum { mp4, avi, mkv } = .mp4,
        resolution: [2]u32,
        quality: ?enum { low, medium, high } = null,
        verbose: bool = false,
    };

    const GitCommand = union(enum) {
        remote: union(enum) {
            add: struct { name: []const u8, url: []const u8 },
            remove: []const u8,
        },
        status: void,
    };

    const GrepArgs = struct {
        struct {
            @"ignore-case": ?void = null,
            @"line-number": ?void = null,
        },
        []const []const u8,
    };

    const types = .{ EncodeOptions, GitCommand, GitCommand, GitCommand, GrepArgs };

    var arguments = [_][10][:0]const u8{
        .{ "<arg0>", "--input", "video.mp4", "--output", "result.mkv", "--format", "mkv", "--resolution", "1920", "1080" },
        .{ "<arg0>", "remote", "add", "--name", "origin", "--url", "git@github.com:user/repo", "", "", "" },
        .{ "<arg0>", "remote", "remove", "upstream", "", "", "", "", "", "" },
        .{ "<arg0>", "status", "", "", "", "", "", "", "", "" },
        .{ "<arg0>", "--ignore-case", "pattern", "file1.txt", "file2.txt", "", "", "", "", "" },
    };

    const expected = .{
        EncodeOptions{ .input = "video.mp4", .output = "result.mkv", .format = .mkv, .resolution = .{ 1920, 1080 }, .quality = null },
        GitCommand{ .remote = .{ .add = .{ .name = "origin", .url = "git@github.com:user/repo" } } },
        GitCommand{ .remote = .{ .remove = "upstream" } },
        GitCommand{ .status = {} },
        GrepArgs{ .{ .@"ignore-case" = {} }, @as([]const []const u8, &.{ "pattern", "file1.txt", "file2.txt", "", "", "", "", "" }) },
    };

    inline for (types, &arguments, expected) |T, *a, e|
        try testing.expectEqualDeep(e, try parse(T, a, allocator));
}
