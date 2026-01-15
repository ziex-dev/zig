const std = @import("std.zig");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const comptimePrint = std.fmt.comptimePrint;
const Io = std.Io;
const Writer = Io.Writer;
const StdArgs = std.process.Args;
const ArenaAllocator = std.heap.ArenaAllocator;
const StructField = std.builtin.Type.StructField;
const mem = std.mem;
const Allocator = mem.Allocator;

pub const Options = struct {
    /// Parsing/validation errors and the long `--help` documentation will be written to this writer.
    /// Any error while writing is silently ignored.
    /// When this value is null, stderr is used.
    terminal: ?Io.Terminal = null,

    /// The program name used in the help output, e.g. "my-command" in "Usage: my-command [options] ...".
    /// By default uses the value of `Args.arg0` or the process's first argument (`argv[0]`).
    /// When there is no `argv[0]`, the default is `"<prog>"`.
    arg0: ?[]const u8 = null,

    /// Call `std.process.exit` with an error status instead of returning `error.Usage` or `error.Help`.
    exit: bool = true,
};

pub const Error = error{
    /// Caused by unrecognized option names, values that cannot be parsed into the appropriate field type,
    /// missing arguments for fields with no default value, and other similar parsing errors.
    /// See also `options.exit`, which can supersede this error.
    Usage,
    /// The --help argument was given (and `options.exit` resolved to `false`).
    Help,
} || Allocator.Error;

/// Parses CLI args from a `std.process.ArgIterator` according to the configuration in `Args`.
/// `Args` is a struct that you define looking like this:
/// ```zig
/// const Args = struct {
///     pub const arg0 = "myprog";
///     pub const description = "this program does a thing";
///     named: struct {
///         verbose: bool = false,
///         output: [:0]const u8,
///         pub const help = .{
///             .output = "path to output file",
///         },
///     },
///     positional: struct {
///         input: []const u8,
///         args: []const []const u8 = &.{},
///         pub const help = .{
///             .input = "path to input file",
///         };
///     },
/// };
/// ```
///
/// Which results in this generated `--help` output:
/// ```
/// Usage: myprog --output=string [options] input [args...]
///
/// this program does a thing
///
/// Arguments:
///   input                [string. required] path to input file
///   args                 [string]
///
/// Options:
///   --help               Print this help text and exit.
///   --verbose            [default: no]
///   --output=string      [required] path to output file
/// ```
///
/// Either or both of `named` and `positional` may be omitted, which is effectively equivalent to declaring them as `struct {}`.
/// If `description` is declared, it is concatenated into the help output after the usage line.
/// If `named` or `positional` has a `help` declaration, each field accompanies the appropriate argument in the help text.
///
/// The sequence of arg strings from the `ArgIterator` is parsed to determine named and positional arguments.
///
/// Each arg string takes one of these forms:
/// ```
/// --<name>          (1)
/// --no-<name>       (2)
/// --<name>=<value>  (3)
/// --help            (4)
/// -<alpha><any>     (5) always an error
/// --                (6)
/// <other>           (7)
/// ```
/// Forms (1), (2), and (3) must correspond to a field `Args.named.<name>`; see below for named argument handling.
/// Form (4) immediately prints the long help documentation and exits or returns `error.Help` depending on options.exit.
/// Form (6) signals that all following arg strings are positional.
/// Form (7) following form (1) may be a value to a field `Args.named.<name>`, or is otherwise a positional argument; discussed below.
///
/// Form (5) is always an error.
/// This API does not support single letter aliases like `-v` or `-lA` or named arguments prefixed by only a single hyphen like `-flag`.
/// Form (5) is defined by any arg string where the first byte is '-' and the second byte is `'A'...'Z', 'a'...'z'`
/// (and any following bytes are ignored).
/// A `-9` or other second byte outside the ascii-alpha range is Form (7).
///
/// For forms (1), (2), and (3), let `T` be the type of `Args.named.<name>.value`.
/// `T` may be any of the following:
/// - `bool`
/// - any integer such as `i32`
/// - any float such as `f64`
/// - any `enum` with at least 1 member
/// - a string type, namely `[:0]const u8` or `[]const u8`
/// - a slice type that type `[]C` can coerce into, such as `[]const C`, where `C` is one of:
///     - any integer
///     - any float
///     - any `enum` with at least one member
///     - a string type
///
/// If `T` is `bool`, then form (1) sets it to `true`, form (2) sets it to `false`, and form (3) is not allowed, and a following form (7) is parsed as a positional argument.
/// Otherwise, form (2) is not allowed, and form (3) specifies the `<value>` or form (1) must be followed by a form (8) specifying the `<value>`.
///
/// The `<value>` in forms (3) and (7) is parsed from its string representation:
/// - integers use `std.fmt.parseInt` with base `0`
/// - floats use `std.fmt.parseFloat`
/// - enums use `std.meta.stringToEnum`
/// - strings use the raw value of the string without modification
///
/// Each `Args.named.<name>` may have a default value, which makes the forms (1), (2), (3), and (7) optional.
/// Slice arguments `[]const C` (where `C` is not `u8`) are always considered optional, and the default value will be used if no values were parsed.
/// If a bool argument has no default value, then either form (1) or (2) must be given.
///
/// Each positional arg string corresponds to a field in `Args.positional` in declaration order.
/// Each field in `Args.positional` may have a default value, making the corresponding argument optional.
/// Fields for required positional arguments must precede fields for optional arguments.
/// For each field, let `T` be its type.
/// Similar to `Args.named` described above, `T` may be any of the following:
/// - any integer
/// - any float
/// - any `enum` with at least 1 member
/// - a string type, namely `[]const u8`, `[]u8`, `[:0]const u8` and `[:0]u8`
///
/// Optional positional arguments may be declared using a default value.
/// If the argument is not parsed, then the value will be the declared default value.
/// Optional positional arguments _must_ be declared after all required positional arguments; required positional arguments may _not_ be declared after optional positional arguments.
///
/// The final positional argument may also be a slice type that type `[]T` can coerce into (where `T` is described above).
/// Such a positional argument is described as the "variadic positional" for future reference.
/// The variadic positional is always assumed to be optional, and is only parsed after all other (required _and_ optional) arguments have been parsed.
/// If no variadic positional arguments are parsed, the value is the default value declared, or the empty list if no default is declared.
///
/// This module may generate a usage string and help text for the given program, and will use an appropriate value as the arg 0 in such documentation.
/// This arg 0 value is selected according to priority:
/// - The value of `pub const arg0` declared on `Args`, if it exists
/// - The value of `Options.arg0` if non-null
/// - The first value of the `argv` if not using `parseSlice`
/// - The string "<prog>". This is the least-descriptive value, and it's recommended that one of the above options are used
///
/// It's possible to override the automatically-generated usage string by declaring `pub const usage` on the given `Args` struct.
/// This API assumes the presence of any string templates `{s}` represents `arg0` as described above.
/// The value must coerce to `[]const u8`.
///
/// It's also possible to override the automatically-generated long help documentation by declaring a public constant named `help` in `Args`.
/// This API automatically prepends help text with a usage string as described above for consistency.
/// The help text override must coerce to `[]const u8`.
///
/// ```zig
/// const Args = struct {
///     pub const arg0 = "your-command";
///     pub const usage = "usage: {s} --your-usage goes-here";
///     pub const help =
///         \\options:
///         \\  --help     Print this help text and exit.
///         \\  [...]
///         \\
///     ;
///     named: struct {
///         // [...]
///     },
///     positional: struct {
///         // [...]
///     },
/// };
/// ```
///
/// If a parsing/validation error occurs or the `--help` arg is given, this function calls `std.process.exit` with `1` (exported as `usage_exit_code`) and `0` (exported as `help_exit_code`) respectively, unless `options.exit` is set to `false`, in which case parsing/validation errors return `error.Usage` and `--help` returns `error.Help`.
/// Allocator errors are always returned from the function.
///
/// It is not possible to precisely deallocate the memory allocated by this function.
/// An `ArenaAllocator` is recommended to prevent memory leaks.
pub fn parse(comptime Args: type, arena: Allocator, args: StdArgs, options: Options) Error!Args {
    var iter = try args.iterateAllocator(arena);
    const argv0 = iter.next();
    var opts = options;
    opts.arg0 = opts.arg0 orelse argv0 orelse "<prog>";
    return innerParse(Args, arena, [:0]const u8, &iter, opts);
}

/// Like `parse`, but allows specifying a custom arg iterator.
/// `argv` is a mutable pointer to a type has a method:
/// ```
/// pub fn next(self: *Self) ?String { ... }
/// ```
/// Where `String` is `[]const u8` or `[:0]const u8`.
///
/// If `options.arg0` is `null`, then the first result of `argv.next()` is used by default; otherwise, this value is ignored.
///
/// If a parsing/validation error occurs or the `--help` arg is given,
/// this function returns `error.Usage` or `error.Help` respectively,
/// unless `options.exit` is set to `true`, in which case `std.process.exit` is called with `usage_exit_code` (`1`) or `help_exit_code` (`0`) respectively.
/// Allocator errors are always returned from the function.
///
/// An `ArenaAllocator` is recommended to cleanup the memory allocated from this function.
pub fn parseIter(comptime Args: type, arena: Allocator, argv: anytype, options: Options) Error!Args {
    const NextFn = @FieldType(@typeInfo(@TypeOf(argv)).pointer.child, "next");
    const String = @typeInfo(@typeInfo(NextFn).@"fn".return_type.?).optional.child;
    const argv0: String = argv.next().?;
    var opts = options;
    opts.arg0 = opts.arg0 orelse argv0 orelse "<prog>";
    return innerParse(Args, arena, String, argv, opts);
}

fn ArgIteratorSlice(comptime String: type) type {
    return struct {
        slice: []const String,
        index: usize = 0,

        pub fn next(self: *@This()) ?switch (String) {
            []const u8, []u8 => []const u8,
            [:0]const u8, [:0]u8 => [:0]const u8,
            else => unreachable,
        } {
            if (self.index >= self.slice.len) return null;
            const result = self.slice[self.index];
            self.index += 1;
            return result;
        }
    };
}

/// Like `parse`, but takes a slice of strings in place of using an `ArgIterator`.
/// `argv` must be either be a slice of `String` or a single-item pointer to an array of `String`,
/// where `String` is `[]const u8` or `[:0]const u8`.
///
/// Unlike `parse` and `parseIter`, this function does not use the first item of `argv` as `arg0`.
/// Use `options.arg0` instead.
///
/// If a parsing/validation error occurs or the `--help` arg is given,
/// this function returns `error.Usage` or `error.Help` respectively,
/// unless `options.exit` is set to `true`, in which case `std.process.exit` is called with `usage_exit_code` (`1`) or `help_exit_code` (`0`) respectively.
/// Allocator errors are always returned from the function.
///
/// An `ArenaAllocator` is recommended to cleanup the memory allocated from this function.
pub fn parseSlice(comptime Args: type, arena: Allocator, argv: anytype, options: Options) Error!Args {
    const String = std.meta.Elem(@TypeOf(argv));
    switch (String) {
        []const u8, [:0]const u8, []u8, [:0]u8 => {},
        else => switch (@typeInfo(String)) {
            .array => |array| if (array.child != u8) @compileError("expected argv to be a span of `[]const u8` or similar"),
            else => @compileError("expected argv to be a span of `[]const u8` or similar"),
        },
    }
    var iter: ArgIteratorSlice(String) = .{ .slice = argv };
    var opts = options;
    opts.arg0 = opts.arg0 orelse "<prog>";
    return innerParse(Args, arena, String, &iter, opts);
}

test parseSlice {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            example_required: []const u8,
            example_optional: [:0]const u8 = "-",
            level: i32 = -1,
            flag: bool = true,
            @"enum-option": enum { auto, always, never } = .auto,
        },
        positional: struct {
            args: []const []const u8 = &.{},
        },
    };
    const args = try parseSlice(Args, allocator, &[_][]const u8{
        "--example_required", "a.txt",
        // --example_optional not given
        "--level=0xff",       "--no-flag",
        "--enum-option",      "always",
        "positional1",        "positional2",
        "-12345678",          "--",
        "--positional4",      "--positional=5",
    }, .{});

    try testing.expectEqualDeep(Args{
        .named = .{
            .example_required = "a.txt",
            .example_optional = "-",
            .level = 255,
            .flag = false,
            .@"enum-option" = .always,
        },
        .positional = .{ .args = &.{ "positional1", "positional2", "-12345678", "--positional4", "--positional=5" } },
    }, args);
}

fn innerParseHelp(comptime Args: type, options: Options) error{Help}!noreturn {
    const terminal = options.terminal orelse std.debug.lockStderr(&.{}).terminal();
    defer if (options.terminal == null) std.debug.unlockStderr();
    // Note: arg0 should always be set by public API
    printHelpArg0(Args, terminal.writer, options.arg0.?) catch {};
    if (options.exit) std.process.exit(help_exit_code);
    return error.Help;
}

/// Prints a usage error, and follows the behavior according to `options`.
pub fn usageError(comptime Args: type, options: Options, comptime fmt: []const u8, args: anytype) error{Usage}!noreturn {
    const term = options.terminal orelse std.debug.lockStderr(&.{}).terminal();
    defer if (options.terminal == null) std.debug.unlockStderr();
    print: {
        term.setColor(.red) catch break :print;
        term.writer.writeAll("error") catch break :print;
        term.setColor(.reset) catch break :print;
        term.writer.print(": " ++ fmt ++ "\n", args) catch break :print;
        printUsageArg0(Args, term.writer, options.arg0.?) catch break :print;
    }
    if (options.exit) std.process.exit(usage_exit_code);
    return error.Usage;
}

fn innerParse(comptime Args: type, gpa: Allocator, comptime String: type, iter: anytype, options: Options) Error!Args {
    // argv0 has already been consumed.
    const string_has_sentinel = switch (String) {
        []const u8 => false,
        [:0]const u8 => true,
        else => unreachable,
    };

    // Do all comptime checks up front so that we can be sure any compile error the user sees is the one we wrote.
    const named_fields, const positional_fields = comptime reflectArgs(Args);

    var named_array_lists: ArrayListsForFields(named_fields) = .{};
    var positional_array_lists: ArrayListsForFields(positional_fields) = .{};

    var result: Args = undefined;

    var named_fields_seen = [_]bool{false} ** named_fields.len;
    var positional_field_index: usize = 0;
    var the_rest_is_positional = false;

    argparse: while (iter.next()) |arg| {
        if (!the_rest_is_positional) {
            if (mem.startsWith(u8, arg, "--")) {
                const arg_rest: String = if (string_has_sentinel) arg[2.. :0] else arg[2..];
                if (arg_rest.len == 0) { // handle "--"
                    the_rest_is_positional = true;
                    continue :argparse;
                }

                if (mem.eql(u8, arg_rest, "help")) try innerParseHelp(Args, options);

                // split on "="
                const probably_name: []const u8, const immediate_value: ?String =
                    if (mem.indexOfScalar(u8, arg_rest, '=')) |equals| .{
                        arg_rest[0..equals],
                        if (string_has_sentinel) arg_rest[equals + 1 .. :0] else arg_rest[equals + 1 ..],
                    } else .{ arg_rest, null };

                const @"no-": bool, const name =
                    if (mem.cutPrefix(u8, probably_name, "no-")) |name|
                        .{ true, name }
                    else
                        .{ false, probably_name };

                inline for (named_fields, 0..) |field, i| {
                    if (mem.eql(u8, field.name, name)) {
                        named_fields_seen[i] = true;
                        if (field.type == .bool) {
                            if (immediate_value) |val| try usageError(Args, options, "unexpected value for argument --{s}: {s}", .{
                                probably_name, if (val.len == 0) "''" else val,
                            });
                            @field(result.named, field.name) = !@"no-";
                            continue :argparse;
                        }

                        if (@"no-") break;
                        const arg_value = immediate_value orelse iter.next() orelse try usageError(Args, options, "expected argument after --{s}", .{field.name});
                        const value = try parseValue(Args, gpa, options, field, arg_value);
                        if (field.type == .list) {
                            try @field(named_array_lists, field.name).append(gpa, value);
                        } else {
                            @field(result.named, field.name) = value;
                        }
                        continue :argparse;
                    }
                }

                // no named arguments match
                try usageError(Args, options, "unrecognized argument: {s}", .{arg});
            }

            if (arg.len >= 2 and arg[0] == '-' and std.ascii.isAlphabetic(arg[1])) {
                // Always invalid.
                // Examples: -h, -flag, -I/path
                try usageError(Args, options, "unrecognized argument: {s}", .{arg});
            }
        }

        // Positional.
        // Examples: "", "a", "-", "-1", "other"
        if (positional_field_index >= positional_fields.len) try usageError(Args, options, "unexpected argument: {s}", .{arg});
        inline for (positional_fields, 0..) |field, i| {
            if (positional_field_index == i) {
                const value = try parseValue(Args, gpa, options, field, arg);
                if (field.type == .list) {
                    try @field(positional_array_lists, field.name).append(gpa, value);
                } else {
                    @field(result.positional, field.name) = value;
                    positional_field_index += 1;
                }
                continue :argparse;
            }
        }

        try usageError(Args, options, "extra argument: {s}", .{arg});
    }

    // Fill values.
    inline for (named_fields, 0..) |field, i| {
        if (!named_fields_seen[i]) {
            if (field.defaultValue()) |default| {
                @field(result.named, field.name) = default;
            } else {
                try usageError(Args, options, "missing required argument: {s}", .{field.namedFlagUsage()});
            }
        } else if (field.type == .list) {
            @field(result.named, field.name) = try @field(named_array_lists, field.name).toOwnedSlice(gpa);
        }
    }

    inline for (positional_fields, 0..) |field, i| {
        if (field.type == .list) {
            comptime assert(i == positional_fields.len - 1); // there's only 1 allowed positional list
            var values = try @field(positional_array_lists, field.name).toOwnedSlice(gpa);
            if (values.len == 0 and field.default_value_ptr != null) {
                values = try gpa.dupe(field.type.elemType(), field.defaultValue().?);
            }
            @field(result.positional, field.name) = values;
        } else if (positional_field_index <= i) {
            if (field.defaultValue()) |default| {
                @field(result.positional, field.name) = default;
            } else {
                try usageError(Args, options, "missing required argument: {s}", .{field.name});
            }
        }
    }

    return result;
}

fn parseValue(comptime Args: type, gpa: Allocator, options: Options, comptime field: ArgField, arg_value: anytype) !field.type.elemType() {
    return switch (field.type.flatten()) {
        .bool => comptime unreachable, // Handled elsewhere.
        .float => |Float| std.fmt.parseFloat(Float, arg_value) catch |err| try usageError(Args, options, "unable to parse --{s}={s}: {t}", .{ field.name, arg_value, err }),
        .int => |Int| std.fmt.parseInt(Int, arg_value, 0) catch |err| try usageError(Args, options, "unable to parse --{s}={s}: {t}", .{ field.name, arg_value, err }),
        .string => arg_value,
        .cstring => if (@TypeOf(arg_value) == []const u8) try gpa.dupeZ(u8, arg_value) else arg_value,
        .@"enum" => |Enum| std.meta.stringToEnum(Enum, arg_value) orelse try usageError(Args, options, "unable to parse --{s}={s}, expected one of: {s}", .{ field.name, arg_value, enumValuesString(Enum) }),
        .list => unreachable, // flattened
    };
}

const ArgType = union(enum) {
    bool,
    @"enum": type,
    float: type,
    int: type,
    string,
    cstring,
    list: ListElem,

    const ListElem = union(enum) {
        int: type,
        float: type,
        string,
        cstring,
        @"enum": type,

        fn toType(comptime elem: ListElem) type {
            return switch (elem) {
                .int, .float, .@"enum" => |Passthru| Passthru,
                .string => []const u8,
                .cstring => [:0]const u8,
            };
        }
    };

    /// The type of the field
    fn toType(comptime at: ArgType) type {
        return switch (at) {
            .bool => bool,
            .float, .int, .@"enum" => |Passthru| Passthru,
            .string => []const u8,
            .cstring => [:0]const u8,
            .list => |elem| []const elem.toType(),
        };
    }

    /// The type of arguments being parsed for the field
    fn elemType(comptime at: ArgType) type {
        return switch (at) {
            .bool => bool,
            .float, .int, .@"enum" => |Passthru| Passthru,
            .string => []const u8,
            .cstring => [:0]const u8,
            .list => |elem| elem.toType(),
        };
    }

    fn flatten(comptime at: ArgType) ArgType {
        if (at != .list) return at;
        return switch (at.list) {
            inline else => |payload, tag| @unionInit(ArgType, @tagName(tag), payload),
        };
    }
};

const ArgField = struct {
    name: []const u8,
    type: ArgType,
    default_value_ptr: ?*const anyopaque,

    fn namedFlagUsage(comptime field: ArgField) []const u8 {
        return comptime switch (field.type.flatten()) {
            .bool => "--[no-]" ++ field.name,
            .@"enum" => |Enum| "--" ++ field.name ++ "=[" ++ enumValuesString(Enum) ++ "]",
            .float => "--" ++ field.name ++ "=float",
            .int => "--" ++ field.name ++ "=int",
            .string, .cstring => "--" ++ field.name ++ "=string",
            else => unreachable,
        };
    }

    fn defaultValue(comptime field: ArgField) ?field.type.toType() {
        const dp: *const field.type.toType() = @ptrCast(@alignCast(field.default_value_ptr orelse return null));
        return dp.*;
    }

    fn of(comptime sf: StructField) ArgField {
        if (sf.is_comptime) @compileError("Comptime args are not supported" ++ sf.name);
        if (mem.eql(u8, sf.name, "help")) @compileError("Args cannot be named 'help'.");
        if (mem.startsWith(u8, sf.name, "no-")) @compileError("Args may not have 'no-' prefix: " ++ sf.name ++ "\nHint: use a bool argument in Args.named, and --<name> and --no-<name> will set the value to true or false.");
        if (mem.indexOfScalar(u8, sf.name, '=')) |_| @compileError("Arg names may not contain '=': " ++ sf.name);
        const at: ArgType = switch (sf.type) {
            bool => .bool,
            []const u8 => .string,
            [:0]const u8 => .cstring,
            []const []const u8 => .{ .list = .string },
            []const [:0]const u8 => .{ .list = .cstring },
            else => |T| switch (@typeInfo(T)) {
                .int => .{ .int = T },
                .float => .{ .float = T },
                .@"enum" => |@"enum"| type: {
                    if (@"enum".fields.len == 0) @compileError("Empty enums are not allowed: " ++ sf.name ++ " (" ++ @typeName(T) ++ ")");
                    break :type .{ .@"enum" = T };
                },
                .pointer => |pointer| type: {
                    if (pointer.size != .slice) @compileError("Only slice pointers are supported: " ++ sf.name ++ " (" ++ @typeName(T) ++ ")");
                    const Elem = pointer.child;
                    switch (@typeInfo(Elem)) {
                        .@"enum" => break :type .{ .list = .{ .@"enum" = Elem } },
                        .int => break :type .{ .list = .{ .int = Elem } },
                        .float => break :type .{ .list = .{ .float = Elem } },
                        else => @compileError("Unsupported slice argument type: " ++ sf.name ++ " (" ++ @typeName(T) ++ ")"),
                    }
                },
                else => @compileError("Unsupported argument type: " ++ sf.name ++ " (" ++ @typeName(T) ++ ")"),
            },
        };
        return .{
            .name = sf.name,
            .type = at,
            .default_value_ptr = sf.default_value_ptr,
        };
    }
};

fn reflectArgs(comptime Args: type) struct { []const ArgField, []const ArgField } {
    var has_named = false;
    var has_positional = false;
    inline for (@typeInfo(Args).@"struct".fields) |field| {
        if (mem.eql(u8, field.name, "named")) {
            has_named = true;
        } else if (mem.eql(u8, field.name, "positional")) {
            has_positional = true;
        } else @compileError("unrecognized Args field: " ++ field.name);
    }

    const named_fields = if (has_named) @typeInfo(@FieldType(Args, "named")).@"struct".fields else &.{};
    var named_args: [named_fields.len]ArgField = undefined;
    inline for (named_fields, 0..) |sf, i| {
        named_args[i] = .of(sf);
    }

    const positional_fields = if (has_positional) @typeInfo(@FieldType(Args, "positional")).@"struct".fields else &.{};
    var positional_args: [positional_fields.len]ArgField = undefined;
    var has_optionals = false;
    inline for (positional_fields, 0..) |sf, i| {
        const arg: ArgField = .of(sf);
        switch (arg.type) {
            .bool => @compileError("Args.positional cannot have bool fields: " ++ arg.name),
            .list => {
                if (i != positional_fields.len - 1) @compileError("Args.positional may only have a variadic argument as its last argument: " ++ arg.name);
            },
            else => {},
        }

        if (arg.default_value_ptr) |_| {
            has_optionals = true;
        } else if (has_optionals and arg.type != .list) @compileError("Args.positional cannot have required arguments after optional arguments: " ++ arg.name);

        positional_args[i] = arg;
    }

    return .{ &named_args, &positional_args };
}

fn ArrayListsForFields(comptime fields: []const ArgField) type {
    // Declare and initialize an ArrayList(C) for every []const C field (other than u8).
    comptime var names: [fields.len][]const u8 = undefined;
    comptime var types: [fields.len]type = undefined;
    comptime var attrs: [fields.len]StructField.Attributes = undefined;
    comptime var len: usize = 0;
    inline for (fields) |field| {
        if (field.type == .list) {
            names[len] = field.name;
            const Elem = field.type.list.toType();
            const ArrayList = std.ArrayList(Elem);
            types[len] = ArrayList;
            attrs[len] = .{ .default_value_ptr = &ArrayList.empty };
            len += 1;
        }
    }
    return @Struct(.auto, null, names[0..len], types[0..len], attrs[0..len]);
}

fn enumValuesString(comptime Enum: type) []const u8 {
    comptime var values_str: []const u8 = "";
    inline for (@typeInfo(Enum).@"enum".fields) |enum_field| {
        if (values_str.len > 1) {
            values_str = values_str ++ ",";
        }
        values_str = values_str ++ enum_field.name;
    }
    return values_str;
}

/// Standard exit code for usage errors.
pub const usage_exit_code = 1;

/// Print the program's usage string to the given writer and exit.
/// If `always_exit` is false and `writer` returns an error, returns the error instead.
pub inline fn printUsageAndExit(comptime Args: type, writer: *Io.Writer, always_exit: bool) !noreturn {
    printUsage(Args, writer) catch |err| if (!always_exit) return err;
    std.process.exit(usage_exit_code);
}

/// Print the program's usage string using the given fallback `arg0` to the given writer and exit.
/// If `Args.arg0` is defined, it is used instead.
/// If `always_exit` is false and `writer` returns an error, returns the error instead.
pub fn printUsageArg0AndExit(comptime Args: type, writer: *Io.Writer, arg0: []const u8, always_exit: bool) !noreturn {
    printUsageArg0(Args, writer, arg0) catch |err| if (!always_exit) return err;
    std.process.exit(usage_exit_code);
}

/// Print the program's usage string to the given writer.
pub fn printUsage(comptime Args: type, writer: *Io.Writer) Io.Writer.Error!void {
    try printUsageArg0(Args, writer, "<prog>");
}

test printUsage {
    const Args1 = struct {
        pub const description = "my description";

        named: struct {
            foo: [:0]const u8,
            bar: bool = false,
            baz: u8 = 0,
            quux: f32 = -1,
            quuz: i32,

            pub const help = .{
                .foo = "does a foo thing",
            };
        },
        positional: struct {
            foo: [:0]const u8,
            bar: u32,
            baz: [:0]const u8 = "baz thing",
            quux: []const []const u8,
        },
    };

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var aw: Writer.Allocating = .init(gpa);
    try printUsage(Args1, &aw.writer);
    try testing.expectEqualStrings("Usage: <prog> --foo=string --quuz=int [options...] <foo> <bar> [baz] [quux...]\n", aw.written());

    const Args2 = struct {
        const usage = "my custom usage";
        named: @FieldType(Args1, "named"),
        positional: @FieldType(Args1, "positional"),
    };

    aw.clearRetainingCapacity();
    try printUsage(Args2, &aw.writer);
    try testing.expectEqualStrings("my custom usage\n", aw.written());
}

/// Print the program's usage string to the given writer with the given fallback `arg0` value.
/// If `Args.arg0` is defined, it is used instead.
pub fn printUsageArg0(comptime Args: type, writer: *Io.Writer, arg0: []const u8) Io.Writer.Error!void {
    const usage, const has_arg0_fmt = comptime getUsageFmt(Args);
    if (has_arg0_fmt) {
        try writer.print(usage, .{arg0});
    } else {
        try writer.writeAll(usage);
    }
}

test printUsageArg0 {
    const Args1 = struct {
        pub const arg0 = "fooprog";
        pub const description = "my description";

        named: struct {
            foo: [:0]const u8,
            bar: bool = false,
            baz: u8 = 0,
            quux: f32 = -1,
            quuz: i32,

            pub const help = .{
                .foo = "does a foo thing",
            };
        },
        positional: struct {
            foo: [:0]const u8,
            bar: u32,
            baz: [:0]const u8 = "baz thing",
            quux: []const []const u8,
        },
    };

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var aw: Writer.Allocating = .init(gpa);
    try printUsageArg0(Args1, &aw.writer, "myprog");
    try testing.expectEqualStrings("Usage: fooprog --foo=string --quuz=int [options...] <foo> <bar> [baz] [quux...]\n", aw.written());
}

/// Returns a generated usage fmt string for the given Args type, and whether a string template for `arg0` is present.
///
/// A string template for `arg0` is only present when `Args.arg0` is not defined.
pub fn getUsageFmt(comptime Args: type) struct { []const u8, bool } {
    return comptime fmt: {
        const arg0: ?[]const u8 = if (@hasDecl(Args, "arg0")) Args.arg0 else null;
        if (@hasDecl(Args, "usage")) {
            var usage: []const u8 = Args.usage;
            if (!mem.endsWith(u8, usage, "\n")) usage = usage ++ "\n";
            if (hasAtLeastOneStringLiteral(usage)) {
                break :fmt if (arg0) |s|
                    .{ comptimePrint(usage, .{s}), false }
                else
                    .{ usage, true };
            } else {
                break :fmt .{ usage, false };
            }
        }

        const named_fields, const positional_fields = reflectArgs(Args);
        var usage: []const u8 = "Usage: " ++ (if (arg0) |s| s else "{s}");
        var at_least_one_optional_named_argument = false;

        for (named_fields) |field| {
            if (field.default_value_ptr != null or field.type == .list) {
                // Don't mention optional named arguments.
                at_least_one_optional_named_argument = true;
            } else {
                usage = usage ++ " " ++ field.namedFlagUsage();
            }
        }

        if (at_least_one_optional_named_argument) {
            usage = usage ++ " [options...]";
        }

        for (positional_fields) |field| {
            if (field.default_value_ptr != null or field.type == .list) {
                usage = comptimePrint("{s} [{s}{s}]", .{
                    usage, field.name, if (field.type == .list) "..." else "",
                });
            } else {
                usage = comptimePrint("{s} <{s}>", .{
                    usage, field.name,
                });
            }
        }

        break :fmt .{ usage ++ "\n", arg0 == null };
    };
}

test getUsageFmt {
    const Args = struct {
        pub const arg0 = "program";
        named: struct {
            optional: bool = false,
            required: bool,
        },
        positional: struct {
            required: []const u8,
            optional: []const u8 = "",
        },
    };

    const fmt, const hasFmt = getUsageFmt(Args);
    try testing.expect(!hasFmt); // arg0 provided by `Args.arg0`
    try testing.expectEqualStrings(
        \\Usage: program --[no-]required [options...] <required> [optional]
        \\
    , fmt);
}

fn hasAtLeastOneStringLiteral(comptime fmt: []const u8) bool {
    @setEvalBranchQuota(@as(comptime_int, fmt.len) * 1000);
    comptime var i = 0;
    inline while (comptime mem.indexOfScalarPos(u8, fmt, i, '{')) |pos| {
        i = pos + 1;
        if (i >= fmt.len or fmt[i] == '{') {
            // skip escaped {{
            i += 1;
            continue;
        }

        const start = i;
        const end = comptime mem.indexOfScalarPos(u8, fmt, i, '}') orelse return false;
        i = end + 1;

        const placeholder: std.fmt.Placeholder = comptime .parse(fmt[start..end]);
        if (comptime mem.eql(u8, placeholder.specifier_arg, "s")) {
            return true;
        }
    }

    return false;
}

test hasAtLeastOneStringLiteral {
    try testing.expect(hasAtLeastOneStringLiteral("{s}"));
    try testing.expect(hasAtLeastOneStringLiteral(". {s}. "));
    try testing.expect(hasAtLeastOneStringLiteral(" {s}{{}}{s}.  {s}"));
    try testing.expect(hasAtLeastOneStringLiteral("{s}}")); // Note: this follows Io.Writer.print's behavior, but results in a compile error

    try testing.expect(!hasAtLeastOneStringLiteral(""));
    try testing.expect(!hasAtLeastOneStringLiteral("s"));
    try testing.expect(!hasAtLeastOneStringLiteral("{{s}}"));
    try testing.expect(!hasAtLeastOneStringLiteral("{{s}"));
}

inline fn escapeFmt(comptime s: []const u8) []const u8 {
    var result: []const u8 = "";
    comptime var cursor = 0;
    for (s, 0..) |c, i| {
        switch (c) {
            '{', '}' => {
                result = result ++ s[cursor..i] ++ &.{ c, c };
                cursor = i + 1;
            },
            else => {},
        }
    }
    result = result ++ s[cursor..];
    return result;
}

/// Standard exit code when `--help` is provided on the command line.
pub const help_exit_code = 0;

/// Print the program's help text to the given writer and exit.
/// If there's a write error and `always_exit` is false, returns the error instead.
pub fn printHelpAndExit(comptime Args: type, writer: *Io.Writer, always_exit: bool) Io.Writer.Error!noreturn {
    printHelp(Args, writer) catch |err| if (!always_exit) return err;
    std.process.exit(help_exit_code);
}

/// Print the program's help text using the given arg0 fallback and exit.
/// The given arg0 is only used if `Args.arg0` is not defined.
/// If there's a write error and `always_exit` is false, returns the error instead.
pub fn printHelpArg0AndExit(comptime Args: type, writer: *Io.Writer, arg0: []const u8, always_exit: bool) Io.Writer.Error!noreturn {
    printHelpArg0(Args, writer, arg0) catch |err| if (!always_exit) return err;
    std.process.exit(help_exit_code);
}

/// Print the program's help text to the given writer.
pub fn printHelp(comptime Args: type, writer: *Io.Writer) Io.Writer.Error!void {
    try printHelpArg0(Args, writer, "<prog>");
}

test printHelp {
    const Args = struct {
        pub const arg0 = "hello";
        pub const description = "my special description";

        named: struct {
            foo: [:0]const u8 = "",
            bar: []const u8,
            baz: u32 = 10,
            quux: i8 = -1,
            quuz: f32 = -420,
            foobar: bool = false,
            barfoo: bool,
            foobaz: []const []const u8,

            pub const help = .{
                .foo = "does a foo thing",
                .bar = "does a bar thing",
                .quuz = "Nice.",
            };
        },
        positional: struct {
            foo: []const u8,
            bar: []const u8 = "",
            baz: []const []const u8,

            pub const help = .{
                .foo = "a special foo thing",
                .baz = "not-so-special baz thing",
            };
        },
    };

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var aw: Writer.Allocating = .init(gpa);
    try printHelp(Args, &aw.writer);
    try testing.expectEqualStrings(
        \\Usage: hello --bar=string --[no-]barfoo [options...] <foo> [bar] [baz...]
        \\
        \\my special description
        \\
        \\Arguments:
        \\  foo                 [string. required] a special foo thing
        \\  bar                 [string. default: '']
        \\  baz...              [string] not-so-special baz thing
        \\
        \\Options:
        \\  --help              Print this help text and exit.
        \\  --foo=string        [default: ''] does a foo thing
        \\  --bar=string        [required] does a bar thing
        \\  --baz=int           [default: 10]
        \\  --quux=int          [default: -1]
        \\  --quuz=float        [default: -420] Nice.
        \\  --[no-]foobar       [default: no]
        \\  --[no-]barfoo       [required]
        \\  --foobaz=string     [multiple]
        \\
    , aw.written());
}

/// Print the program's help text using the given arg0 fallback.
/// The given arg0 is only used if `Args.arg0` is not defined.
pub fn printHelpArg0(comptime Args: type, writer: *Io.Writer, arg0: []const u8) Io.Writer.Error!void {
    const help, const has_arg0_fmt = comptime getHelpFmt(Args);
    if (has_arg0_fmt)
        try writer.print(help, .{arg0})
    else
        try writer.writeAll(help);
}

test printHelpArg0 {
    const Args = struct {
        pub const arg0 = "hello";
        pub const description = "my special description";

        named: struct {
            foo: [:0]const u8 = "",
            bar: []const u8,
            baz: u32 = 10,
            quux: i8 = -1,
            quuz: f32 = -420,
            foobar: bool = false,
            barfoo: bool,
            foobaz: []const []const u8,

            pub const help = .{
                .foo = "does a foo thing",
                .bar = "does a bar thing",
                .quuz = "Nice.",
            };
        },
        positional: struct {
            foo: []const u8,
            bar: []const u8 = "",
            baz: []const []const u8,

            pub const help = .{
                .foo = "a special foo thing",
                .baz = "not-so-special baz thing",
            };
        },
    };

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var aw: Writer.Allocating = .init(gpa);
    try printHelpArg0(Args, &aw.writer, "myprog");
    try testing.expectEqualStrings(
        \\Usage: hello --bar=string --[no-]barfoo [options...] <foo> [bar] [baz...]
        \\
        \\my special description
        \\
        \\Arguments:
        \\  foo                 [string. required] a special foo thing
        \\  bar                 [string. default: '']
        \\  baz...              [string] not-so-special baz thing
        \\
        \\Options:
        \\  --help              Print this help text and exit.
        \\  --foo=string        [default: ''] does a foo thing
        \\  --bar=string        [required] does a bar thing
        \\  --baz=int           [default: 10]
        \\  --quux=int          [default: -1]
        \\  --quuz=float        [default: -420] Nice.
        \\  --[no-]foobar       [default: no]
        \\  --[no-]barfoo       [required]
        \\  --foobaz=string     [multiple]
        \\
    , aw.written());
}

/// Returns a program's help text format string and whether a string template for arg0 is present.
/// The string template is only present when `Args.arg0` is not defined.
/// If `Args.help` is specified, then it is processed with `Args.arg0` if present, but not prepended with `getUsageFmt`.
///
/// If `Args.help` is not specified, then the help format follows this template:
/// ```
/// {usage}
///
/// {description}
///
/// Arguments:
///   {argname}     [{type} {default/required}] {description}
///
/// Options:
///   --help        Print this help text and exit.
///   {argname}     [{default/multiple/required}] {description}
/// ```
///
/// The template has the following caveats:
/// - `{usage}` is the result of `getUsageFmt`
/// - `{description}` is `Args.description` if present. Otherwise, this is omitted.
/// - The `Arguments:` section is omitted if `Args.positional` isn't present or is empty.
/// - If a positional arg is a list, `{argname}` has "..." appended and `{default/required}` is omitted.
/// - If `@TypeOf(Args.positional).help` is omitted, or if `argname` field is omitted from the anonymous struct, then `{description}` is omitted.
/// - If a named arg is a boolean, `{argname}` is `--[no-]{argname}`, otherwise it's `--{argname}={type}`.
/// - If `@TypeOf(Args.named).help` is omitted, or if `argname` field is omitted from the anonymous struct, then `{description}` is omitted
pub fn getHelpFmt(comptime Args: type) struct { []const u8, bool } {
    return comptime fmt: {
        const usage, const has_arg0_fmt = getUsageFmt(Args);
        if (@hasDecl(Args, "help")) {
            const help: []const u8 = usage ++ "\n" ++ Args.help;
            return .{ help, has_arg0_fmt };
        }

        const named_fields, const positional_fields = reflectArgs(Args);
        @setEvalBranchQuota(named_fields.len * 1000 + positional_fields.len * 1000);

        var lhs_max_width = 0;

        var arguments_table: [positional_fields.len]struct { []const u8, []const u8 } = undefined;
        const Positional = if (positional_fields.len > 0) @FieldType(Args, "positional") else struct {};
        const arguments_help = field_help_text(Positional);
        for (positional_fields, 0..) |field, i| {
            const lhs: []const u8 = field.name ++ (if (field.type == .list) "..." else "");
            var rhs: []const u8 = comptimePrint("[{s}{s}]", .{
                switch (field.type.flatten()) {
                    .bool, .list => unreachable,
                    .@"enum" => |Enum| enumValuesString(Enum),
                    .float => "float",
                    .int => "int",
                    .cstring, .string => "string",
                },
                if (field.defaultValue()) |default| switch (field.type) {
                    .bool => unreachable,
                    .@"enum" => comptimePrint(". default: {t}", .{default}),
                    .float, .int => comptimePrint(". default: {d}", .{default}),
                    .cstring, .string => comptimePrint(". default: {s}", .{if (default.len == 0) "''" else default}),
                    .list => "",
                } else if (field.type == .list) "" else ". required",
            });
            if (@field(arguments_help, field.name)) |description| {
                rhs = rhs ++ " " ++ @as([]const u8, if (has_arg0_fmt) escapeFmt(description) else description);
            }

            arguments_table[i] = .{ lhs, rhs };
            lhs_max_width = @max(lhs_max_width, lhs.len);
        }

        var options_table: [named_fields.len + 1]struct { []const u8, []const u8 } = undefined;
        options_table[0] = .{ "--help", "Print this help text and exit." };
        lhs_max_width = @max(lhs_max_width, "--help".len);

        const Named = if (named_fields.len > 0) @FieldType(Args, "named") else struct {};
        const options_help = field_help_text(Named);
        for (named_fields, 1..) |field, i| {
            const lhs: []const u8 = field.namedFlagUsage();
            var rhs: []const u8 = "[";
            if (field.type == .list) {
                rhs = rhs ++ "multiple";
            } else if (field.defaultValue()) |default| {
                rhs = rhs ++ switch (field.type) {
                    .bool => comptimePrint("default: {s}", .{if (default) "yes" else "no"}),
                    .@"enum" => comptimePrint("default: {t}", .{default}),
                    .float, .int => comptimePrint("default: {d}", .{default}),
                    .cstring, .string => comptimePrint("default: {s}", .{if (default.len == 0) "''" else default}),
                    .list => unreachable,
                };
            } else {
                rhs = rhs ++ "required";
            }
            rhs = rhs ++ "]";
            if (@field(options_help, field.name)) |description| {
                rhs = rhs ++ " " ++ @as([]const u8, if (has_arg0_fmt) escapeFmt(description) else description);
            }

            options_table[i] = .{ lhs, rhs };
            lhs_max_width = @max(lhs_max_width, lhs.len);
        }

        var help: []const u8 = usage;
        if (@hasDecl(Args, "description")) {
            help = help ++ "\n" ++ @as([]const u8, Args.description) ++ "\n";
        }

        lhs_max_width += 5; // minimum spacing

        if (positional_fields.len != 0) {
            help = help ++ "\nArguments:\n";
            for (arguments_table) |argument| {
                const lhs, const rhs = argument;
                const middle_spacing = " " ** (lhs_max_width - lhs.len);
                help = help ++ "  " ++ lhs ++ middle_spacing ++ rhs ++ "\n";
            }
        }

        help = help ++ "\nOptions:\n";
        for (options_table) |option| {
            const lhs, const rhs = option;
            const middle_spacing = " " ** (lhs_max_width - lhs.len);
            help = help ++ "  " ++ lhs ++ middle_spacing ++ rhs ++ "\n";
        }


        break :fmt .{ help, has_arg0_fmt };
    };
}

fn field_help_text(comptime Container: type) FieldHelpText(Container) {
    comptime {
        var help: FieldHelpText(Container) = .{};
        if (!@hasDecl(Container, "help")) return help;
        const help_fields = @typeInfo(@TypeOf(Container.help)).@"struct".fields;
        for (help_fields) |field| {
            @field(help, field.name) = @field(Container.help, field.name);
        }
        return help;
    }
}

fn FieldHelpText(comptime Container: type) type {
    return @Struct(
        .auto,
        null,
        std.meta.fieldNames(Container),
        &@splat(?[]const u8),
        &@splat(.{ .default_value_ptr = &@as(?[]const u8, null) }),
    );
}

var failing_writer: Writer = .failing;
const failing_terminal: Io.Terminal = .{ .mode = .no_color, .writer = &failing_writer };
const silent_options = Options{ .terminal = failing_terminal, .exit = false };

test "bool" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            b: bool,
        },
    };

    try testing.expectEqualDeep(Args{ .named = .{ .b = true } }, try parseSlice(Args, allocator, &[_][]const u8{"--b"}, .{}));
    try testing.expectEqualDeep(Args{ .named = .{ .b = false } }, try parseSlice(Args, allocator, &[_][]const u8{"--no-b"}, .{}));
    try testing.expectEqualDeep(Args{ .named = .{ .b = true } }, try parseSlice(Args, allocator, &[_][]const u8{ "--no-b", "--b" }, .{}));
    try testing.expectEqualDeep(Args{ .named = .{ .b = false } }, try parseSlice(Args, allocator, &[_][]const u8{ "--b", "--no-b" }, .{}));

    try testing.expectError(error.Usage, parseSlice(Args, allocator, &[_][]const u8{"--b=true"}, silent_options));
    try testing.expectError(error.Usage, parseSlice(Args, allocator, &[_][]const u8{"--b=false"}, silent_options));
}

test "string" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            a: []const u8,
            b: [:0]const u8,
        },
    };
    const args = try parseSlice(Args, allocator, &[_][:0]const u8{
        "--a", "a",
        "--b", "b",
    }, .{});

    try testing.expectEqualDeep(Args{
        .named = .{
            .a = "a",
            .b = "b",
        },
    }, args);
}

test "ints and floats" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            int_u32: u32,
            int_i32: i32,
            int_u8: u8,
            int_u256: u256,
            float_f32: f32,
            float_f64: f64,
            inf_f32: f32,
            ninf_f64: f64,
        },
    };
    const args = try parseSlice(Args, allocator, &[_][]const u8{
        "--int_u32",   "0xffffffff",
        "--int_i32",   "-0x80000000",
        "--int_u8",    "0o310",
        "--int_u256",  "115792089237316195423570985008687907853269984665640564039457584007913129639935",
        "--float_f32", "1.25",
        "--float_f64", "-0xab.cdef012345p-12",
        "--inf_f32",   "inf",
        "--ninf_f64",  "-INF",
    }, .{});

    try testing.expectEqualDeep(Args{
        .named = .{
            .int_u32 = 0xffffffff,
            .int_i32 = -0x80000000,
            .int_u8 = 0o310,
            .int_u256 = 115792089237316195423570985008687907853269984665640564039457584007913129639935,
            .float_f32 = 1.25,
            .float_f64 = -0xab.cdef012345p-12,
            .inf_f32 = std.math.inf(f32),
            .ninf_f64 = -std.math.inf(f64),
        },
    }, args);

    const Args2 = struct {
        named: struct {
            nan: f64,
        },
    };
    const args2 = try parseSlice(Args2, allocator, &[_][]const u8{
        "--nan", "nAN",
    }, .{});

    try testing.expect(std.math.isNan(args2.named.nan));
}

test "array" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            path: []const []const u8 = &.{},
            id: []const i32 = &.{},
        },
        positional: struct {
            args: []const []const u8 = &.{},
        },
    };

    try testing.expectEqualDeep(Args{
        .named = .{
            .path = &[_][]const u8{ "a", "b", "a" },
            .id = &[_]i32{ 1, -12 },
        },
        .positional = .{
            .args = &[_][]const u8{ "x", "y" },
        },
    }, try parseSlice(Args, allocator, &[_][]const u8{
        "--path", "a",
        "--path", "b",
        "--path", "a",
        "--id",   "1",
        "--id",   "-12",
        "x",      "y",
    }, .{}));
}

test "enum" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            color: enum {
                always,
                never,
                auto,
            },
            guess: enum {
                @"the-only-option",
            },
            signal: enum(u8) {
                KILL = 9,
                TERM = 15,
                VTALRM = 26,
            },
        },
    };
    const args = try parseSlice(Args, allocator, &[_][]const u8{
        "--color",  "always",
        "--guess",  "the-only-option",
        "--signal", "TERM",
    }, .{});

    try testing.expectEqualDeep(Args{
        .named = .{
            .color = .always,
            .guess = .@"the-only-option",
            .signal = .TERM,
        },
    }, args);
}

test "defaults" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            level: i8 = -1,
            ratio: f32 = 0.5,
            path: []const u8 = "-",
            color: enum {
                always,
                never,
                auto,
            } = .auto,
            file: []const []const u8 = &.{},
            force: bool = false,
            cleanup: bool = true,
        },
    };

    try testing.expectEqualDeep(Args{
        .named = .{},
    }, try parseSlice(Args, allocator, &[_][]const u8{}, .{}));
    try testing.expectEqualDeep(Args{
        .named = .{
            .color = .always,
        },
    }, try parseSlice(Args, allocator, &[_][]const u8{ "--color", "always" }, .{}));
    try testing.expectEqualDeep(Args{
        .named = .{
            .file = &[_][]const u8{"file.txt"},
        },
    }, try parseSlice(Args, allocator, &[_][]const u8{ "--file", "file.txt" }, .{}));

    try testing.expectEqualDeep(Args{
        .named = .{
            .force = true,
            .cleanup = false,
        },
    }, try parseSlice(Args, allocator, &[_][]const u8{ "--force", "--no-cleanup" }, .{}));
}

test "positional" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // defaults
    {
        const Args = struct {
            positional: struct {
                level: i8 = -1,
                ratio: f32 = 0.5,
                path: []const u8 = "-",
                color: enum {
                    always,
                    never,
                    auto,
                } = .auto,
                file: []const []const u8 = &.{},
            },
        };

        try testing.expectEqualDeep(Args{
            .positional = .{},
        }, try parseSlice(Args, allocator, &[_][]const u8{}, .{}));
        try testing.expectEqualDeep(Args{
            .positional = .{
                .level = 1,
                .ratio = 2,
                .path = "a.txt",
                .color = .always,
                .file = &[_][]const u8{ "file1", "file2" },
            },
        }, try parseSlice(Args, allocator, &[_][]const u8{ "1", "2", "a.txt", "always", "file1", "file2" }, .{}));
    }

    // required
    {
        const Args = struct {
            positional: struct {
                level: i8,
                ratio: f32,
                path: []const u8,
                color: enum {
                    always,
                    never,
                    auto,
                },
                file: []const []const u8 = &.{},
            },
        };

        try testing.expectError(error.Usage, parseSlice(Args, allocator, &[_][]const u8{}, silent_options));
        try testing.expectError(error.Usage, parseSlice(Args, allocator, &[_][]const u8{ "1", "2", "a.txt" }, silent_options));
        try testing.expectEqualDeep(Args{
            .positional = .{
                .level = 1,
                .ratio = 2,
                .path = "a.txt",
                .color = .always,
            },
        }, try parseSlice(Args, allocator, &[_][]const u8{ "1", "2", "a.txt", "always" }, .{}));
    }
}

test "usage errors" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var aw: Writer.Allocating = .init(allocator);
    const term: Io.Terminal = .{ .mode = .no_color, .writer = &aw.writer };
    const options = Options{ .arg0 = "test-prog", .terminal = term, .exit = false };

    // unrecognized argument
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: []const u8 = "",
        },
    }, allocator, &[_][]const u8{"--bogus"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--bogus") != null);

    // expected argument
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: []const u8 = "",
        },
    }, allocator, &[_][]const u8{"--name"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // --no-<name> for non-bool.
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: []const u8 = "",
        },
    }, allocator, &[_][]const u8{"--no-name"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--no-name") != null);

    // --name=false for bool
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: bool = false,
        },
    }, allocator, &[_][]const u8{"--name=true"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // missing required argument
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: []const u8,
        },
    }, allocator, &[_][]const u8{}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // parse int error
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: i32,
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: []const i32 = &.{},
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // parse float error
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: f32,
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: []const f32 = &.{},
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // parse enum error
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: enum { auto, never, always },
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "abc") != null);
    // Error should suggest the set of options.
    try testing.expect(mem.indexOf(u8, aw.written(), "always") != null);

    // reject single-letter alias-looking arguments
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            z: bool = false,
        },
        positional: struct {
            args: []const []const u8 = &.{},
        },
    }, allocator, &[_][]const u8{"-z"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "-z") != null);

    // expected required positional argument
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        positional: struct {
            input_file: []const u8,
        },
    }, allocator, &[_][]const u8{}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "input_file") != null);
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        positional: struct {
            input_file: []const u8,
            output_file: []const u8 = "",
        },
    }, allocator, &[_][]const u8{}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "input_file") != null);
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        positional: struct {
            input_file: []const u8,
            output_file: []const u8,
            other: []const u8 = "",
        },
    }, allocator, &[_][]const u8{"input.txt"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "output_file") != null);
}

test "help" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var aw: Writer.Allocating = .init(allocator);
    const term: Io.Terminal = .{ .mode = .no_color, .writer = &aw.writer };
    const options = Options{ .arg0 = "test-prog", .terminal = term, .exit = false };

    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            str: []const u8,
            int: i32,
            flag: bool,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    // Because the help output is primarily for humans, don't get too strict in the unit test.
    // Only verify that we see the important stuff that should definitely be there somewhere,
    // but otherwise allow maintainers to adjust the layout, formatting, notation, etc. without causing friction here.
    try testing.expect(mem.indexOf(u8, aw.written(), "test-prog") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "--str=string") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "--int") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "--[no-]flag") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "--help") != null);

    aw.clearRetainingCapacity();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            color: enum { never, auto, always } = .auto,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    // All allowed values for an enum should be spelled out.
    try testing.expect(mem.indexOf(u8, aw.written(), "--color") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "never") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "auto") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "always") != null);

    // Test that arrays are represented differently from scalars somehow.
    aw.clearRetainingCapacity();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            name: []const u8,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const scalar_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            name: []const []const u8 = &.{},
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    try testing.expect(!mem.eql(u8, scalar_help, aw.written()));

    // Default values should be rendered somehow.
    aw.clearRetainingCapacity();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            str: []const u8 = "hello",
            int: i32 = 3,
            f: f32 = 1.25,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "hello") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "3") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "1.25") != null);

    // Test that bool arguments express the default somehow.
    aw.clearRetainingCapacity();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            b: bool,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const bool_required_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            b: bool = true,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const default_true_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            b: bool = false,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const default_false_help = try aw.toOwnedSlice();
    try testing.expect(!mem.eql(u8, bool_required_help, default_true_help));
    try testing.expect(!mem.eql(u8, bool_required_help, default_false_help));
    try testing.expect(!mem.eql(u8, default_true_help, default_false_help));

    // Test that enum arguments express the default somehow.
    aw.clearRetainingCapacity();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            color: enum { never, auto, always },
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const enum_required_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            color: enum { never, auto, always } = .auto,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const default_auto_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            color: enum { never, auto, always } = .never,
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const default_never_help = try aw.toOwnedSlice();
    try testing.expect(!mem.eql(u8, enum_required_help, default_auto_help));
    try testing.expect(!mem.eql(u8, enum_required_help, default_never_help));
    try testing.expect(!mem.eql(u8, default_auto_help, default_never_help));
}

test "minimal" {
    const Args = struct {};

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    _ = try parseSlice(Args, arena.allocator(), &[_][]const u8{}, .{});
}

test "manual deinit" {
    const Args = struct {
        named: struct {
            str_arr: []const []const u8 = &.{},
            int_arr: []const i32 = &.{},
            empty_arr: []const []const u8 = &.{},
        },
        positional: struct {
            args: []const []const u8 = &.{},
        },
    };

    const args = try parseSlice(Args, testing.allocator, &[_][]const u8{
        "--str_arr=hello1", "--str_arr", "hello2",
        "--int_arr=123456", "--int_arr", "789012",
        "positional-12345", "--",        "positi",
    }, .{});

    try testing.expectEqualDeep(Args{
        .named = .{
            .str_arr = &.{ "hello1", "hello2" },
            .int_arr = &.{ 123456, 789012 },
        },
        .positional = .{
            .args = &.{ "positional-12345", "positi" },
        },
    }, args);

    // Surgically cleanup memory.
    testing.allocator.free(args.named.str_arr);
    testing.allocator.free(args.named.int_arr);
    testing.allocator.free(args.named.empty_arr);
    testing.allocator.free(args.positional.args);
    // Should be no memory leak errors now.
}

test "custom help" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var aw: Writer.Allocating = .init(allocator);
    const term: Io.Terminal = .{ .mode = .no_color, .writer = &aw.writer };
    const options = Options{ .arg0 = "unused-prog", .terminal = term, .exit = false };

    const Args = struct {
        pub const usage =
            \\Usage: the-zip-thing --output path [options] input.zip
        ;
        pub const help =
            \\Arguments:
            \\  --output path     where to write the output stuff
            \\  --[no-]force      overwrite output if already exists
            \\  input.zip         the zip file to read
            \\  --help            print this help and exit
            \\
        ;
        named: struct {
            output: []const u8,
            force: bool = false,
        },
        positional: struct {
            args: []const []const u8 = &.{},
        },
    };
    try testing.expectError(error.Help, parseSlice(Args, allocator, &[_][]const u8{"--help"}, options));
    try testing.expectEqualStrings(Args.usage ++ "\n\n" ++ Args.help, aw.written());
}

test "description" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var aw: Writer.Allocating = .init(allocator);
    const term: Io.Terminal = .{ .mode = .no_color, .writer = &aw.writer };
    const options = Options{ .arg0 = "unused-prog", .terminal = term, .exit = false };

    const Args = struct {
        pub const description =
            \\This is a description
        ;
    };
    try testing.expectError(error.Help, parseSlice(Args, allocator, &[_][]const u8{"--help"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), Args.description) != null);
}

test "field help" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var aw: Writer.Allocating = .init(allocator);
    const term: Io.Terminal = .{ .mode = .no_color, .writer = &aw.writer };
    const options = Options{ .arg0 = "unused-prog", .terminal = term, .exit = false };

    const Args = struct {
        named: struct {
            output: []const u8,
            pub const help = .{
                .output = "help for output",
            };
        },
        positional: struct {
            args: []const []const u8 = &.{},
            pub const help = .{
                .args = "help for args",
            };
        },
    };
    try testing.expectError(error.Help, parseSlice(Args, allocator, &[_][]const u8{"--help"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), @FieldType(Args, "named").help.output) != null);
    try testing.expect(mem.indexOf(u8, aw.written(), @FieldType(Args, "positional").help.args) != null);
}
