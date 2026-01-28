//! For parsing a type `Args` from the command line.
//!
//! `Args` is a struct that you define looking like this:
//! ```zig
//! const Args = struct {
//!     pub const info: std.cli.Info = .{
//!         .arg0 = "myprog",
//!         .description = "this program does a thing",
//!         .epilogue = "example: myprog --output o.txt hello.txt",
//!     };
//!
//!     named: struct {
//!         verbose: struct { value: bool = false },
//!         output: struct {
//!             value: [:0]const u8,
//!             pub const info: std.cli.NamedInfo = .{
//!                 .description = "path to output file",
//!                 .short = 'o',
//!             };
//!         },
//!     },
//!     positional: struct {
//!         input: struct {
//!             value: []const u8,
//!             pub const info: std.cli.PositionalInfo = .{
//!                 .description = "path to input file",
//!             };
//!         },
//!         args: struct { value: []const []const u8 = &.{} },
//!     },
//! };
//! ```
//!
//! Which results in this generated `--help` output:
//! ```
//! Usage: myprog --output=string [options...] <input> [args...]
//!
//! this program does a thing
//!
//! Arguments:
//!   input                   [string. required] path to input file
//!   args...                 [string]
//!
//! Options:
//!   -h, --help              Print this help text and exit.
//!   --[no-]verbose          [default: no]
//!   -o, --output=string     [required] path to output file
//!
//! example: myprog --output o.txt hello.txt
//! ```
//!
//! Either or both of `named` and `positional` may be omitted, which is equivalent to declaring them as `struct {}`.
//!
//! Each arg must be defined as a struct with one field, `value`.
//! Named args' types may also declare an `info: NamedInfo`, and positional args' types may also declare an `info: PositionalInfo`.
//! See those types' documentation for more information.
//!
//! Each arg string takes one of these forms:
//! ```
//! --<name>          (1)
//! --no-<name>       (2)
//! --<name>=<value>  (3)
//! --help            (4)
//! -<alpha>+         (5)
//! --                (6)
//! <other>           (7)
//! ```
//!
//! Forms (1), (2), and (3) must correspond to a field `Args.named.<name>`; see below for named argument handling.
//! Form (4) immediately prints the long help documentation and exits or returns `error.Help` depending on options.exit.
//! Form (5) must be a string of letters corresponding to short aliases specified in named args' `info` declaration; see below for short flag handling.
//! Form (6) signals that all following arg strings are positional.
//! Form (7) following form (1) may be a value to a field `Args.named.<name>`, or is otherwise a positional argument; discussed below.
//!
//! For forms (1), (2), (3), and (5), let `T` be the type of `Args.named.<name>.value`.
//! `T` may be any of the following:
//! - `bool`
//! - any integer such as `i32`
//! - any float such as `f64`
//! - any `enum` with at least 1 member
//! - a string type `[:0]const u8` or `[]const u8`
//! - a slice type `[]C` or `[]const C`, where `C` is one of:
//!     - any integer
//!     - any float
//!     - any `enum` with at least one member
//!     - a string type
//! - an optional type `?O`, where `O` is one of:
//!     - any integer
//!     - any float
//!     - any `enum` with at least one member
//!     - a string type
//!
//! If `T` is `bool`, then forms (1) and (5) set it to `true`, form (2) sets it to `false`, form (3) is not allowed, and the following form is parsed separately.
//! If `T` is an optional type, then form (2) sets it to `null`, form (3) specifies the `<value>`, or a form (1) or (5) must be followed by a form (7) specifying the `<value>`.
//! Otherwise, form (2) is not allowed, and form (3) specifies the `<value>`, or forms (1) and (5) must be followed by a form (7) specifying the `<value>`.
//!
//! Form (5) may be a chain of short flags.
//! Each letter in the chain must correspond to a `NamedInfo.short`.
//! A short flag may only be followed by another short flag in the chain if its type is `bool`.
//! If a short flag corresponds to a named argument with a non-`bool` type, then the chain must immediately end, and the `<value>` must be specified in a following form (7).
//!
//! The `<value>` in forms (3) and (7) is parsed from its string representation:
//! - integers use `std.fmt.parseInt` with base `0`
//! - floats use `std.fmt.parseFloat`
//! - enums use `std.meta.stringToEnum`
//! - strings use the raw value of the string without modification
//!
//! Each `Args.named.<name>` may have a default value, which makes the forms (1), (2), (3), (5), and (7) optional.
//!
//! Each positional arg string corresponds to a field in `Args.positional` in declaration order.
//! Each positional arg may have a default value, making the corresponding argument optional.
//! Fields for required positional arguments must precede fields for optional arguments.
//! For each field, let `T` be its type.
//! `T` may be any of the following:
//! - any integer such as `i32`
//! - any float such as `f32`,
//! - any `enum` with at least 1 member
//! - a string type, namely `[]const u8` or `[:0]const u8`
//!
//! Optional positional arguments may be declared using a default value _or_ as any type `?T`, where `T` is described above.
//! If the optional positional argument's type is `?T`, then the declared default value _must_ be `null`, though the absence of a default `null` value will use `null` as the default value anyways.
//! If the argument is not parsed, then the value will be the declared default value.
//! Optional positional arguments _must_ be declared after all required positional arguments; required positional arguments may _not_ be declared after optional positional arguments.
//!
//! The final positional argument may also be a slice type `[]T` or `[]const T` (where `T` is described above).
//! (This documentation refers to such an argument as the "splat positional".)
//! The splat positional is always assumed to be optional, and is only parsed after all other (required _and_ optional) arguments have been parsed.
//! If no splat positional arguments are parsed, the value is the default value specified, or the empty list if no default is specified.

const builtin = @import("builtin");

const std = @import("std.zig");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const comptimePrint = std.fmt.comptimePrint;
const Io = std.Io;
const Writer = Io.Writer;
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
    Usage,
    /// The -h or --help argument was given.
    Help,
} || Allocator.Error;

/// Declare `pub const info: std.cli.Info` on your `Args` type to provide additional information about your program.
pub const Info = struct {
    /// Use this to override the arg0 shown in your usage string.
    /// Only necessary when using the generated usage documentation (when `.usage = null`).
    arg0: ?[]const u8 = null,
    /// Use this to override the generated usage string.
    /// May contain a single `{s}` or multiple `{0s}` fmt templates which will contain the arg0 of the program.
    usage: ?[]const u8 = null,
    /// Use this to override the generated help text.
    /// Prepended with the usage string of the program.
    /// May contain a single `{s}` or multiple `{0s}` fmt templates which will contain the arg0 of the program.
    help: ?[]const u8 = null,
    /// Use this to add a helpful description of your program before arguments/options info in the generated long help text.
    /// Ignored if `.help` is not null.
    /// May contain a single `{s}` or multiple `{0s}` fmt templates which will contain the arg0 of the program.
    description: ?[]const u8 = null,
    /// Use this to add helpful information of your program after arguments/options info in the generated long help text.
    /// Ignore if `.help` is not null.
    /// May contain a single `{s}` or multiple `{0s}` fmt templates which will contain the arg0 of the program.
    epilogue: ?[]const u8 = null,
};

/// Declare `pub const info: std.cli.NamedInfo` in the value type of each named argument to provide additional information about the argument.
pub const NamedInfo = struct {
    /// Use this to add a helpful description of this argument for use in the generated long help text.
    /// Ignored if `Args.info.help` is not null.
    description: ?[]const u8 = null,
    /// Short flag for this named argument.
    /// Must be unique amongst `NamedInfo`s of this `Args` object.
    ///
    /// If `value: bool`, the short flag will only set the value to `true`.
    /// For all other types, the short flag must be immediately followed by another arg containing this arg's value.
    short: ?u8 = null,
};

/// Declare `pub const info: std.cli.PositionalInfo` in the value type of each positional argument to provide additional information about the argument.
pub const PositionalInfo = struct {
    /// Use this to add a helpful description of this argument for use in the generated long help text.
    /// Ignored if `Args.info.help` is not null.
    description: ?[]const u8 = null,
};

/// Parse an `Args` type from the given `std.process.Args`. See this module's
/// documentation for more information on the `Args` type.
///
/// If a parsing/validation error occurs or the `--help` arg is given, this
/// function calls `std.process.exit` with `1` and `0` respectively, unless
/// `options.exit` is set to `false`, in which case parsing/validation errors
/// return `error.Usage` and `--help` returns `error.Help`. Allocator errors are
/// always returned.
///
/// When printing usage or long help text, `arg0` is selected using:
/// - `Args.info.arg0` if non-null
/// - `options.arg0` if non-null
/// - the first value of `args`
///
/// It is not possible to precisely deallocate the memory allocated by this function.
/// An `ArenaAllocator` is recommended to prevent memory leaks.
pub fn parse(comptime Args: type, arena: Allocator, argv: std.process.Args, options: Options) Error!Args {
    var iter = try argv.iterateAllocator(arena);
    const arg0 = iter.next().?;
    var opts = options;
    opts.arg0 = opts.arg0 orelse arg0;
    return innerParse(Args, arena, [:0]const u8, &iter, opts);
}

/// Like `parse`, but allows specifying a custom arg iterator.
/// `argv` is a mutable pointer to a type has a method:
/// ```
/// pub fn next(self: *Self) ?String { ... }
/// ```
/// Where `String` is `[]const u8` or `[:0]const u8`.
///
/// If a parsing/validation error occurs or the `--help` arg is given, this
/// function calls `std.process.exit` with `1` and `0` respectively, unless
/// `options.exit` is set to `false`, in which case parsing/validation errors
/// return `error.Usage` and `--help` returns `error.Help`. Allocator errors are
/// always returned.
///
/// When printing usage or long help text, `arg0` is selected using:
/// - `Args.info.arg0` if non-null
/// - `options.arg0` if non-null
/// - the first value of `argv.next()`
///
/// It is not possible to precisely deallocate the memory allocated by this function.
/// An `ArenaAllocator` is recommended to prevent memory leaks.
pub fn parseIter(comptime Args: type, arena: Allocator, argv: anytype, options: Options) Error!Args {
    const arg0 = argv.next().?;
    const String = @TypeOf(arg0);
    comptime assert(String == []const u8 or [:0]const u8);
    var opts = options;
    opts.arg0 = opts.arg0 orelse arg0;
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

/// Like `parse`, but takes a slice of strings in place of using an iterator.
/// `argv` must be either be a slice of `String` or a single-item pointer to an
/// array of `String`, where `String` is `[]const u8` or `[:0]const u8`.
///
/// If a parsing/validation error occurs or the `--help` arg is given, this
/// function calls `std.process.exit` with `1` and `0` respectively, unless
/// `options.exit` is set to `false`, in which case parsing/validation errors
/// return `error.Usage` and `--help` returns `error.Help`. Allocator errors are
/// always returned.
///
/// When printing usage or long help text, `arg0` is selected using:
/// - `Args.info.arg0` if non-null
/// - `options.arg0` if non-null
/// - `"<prog>"`
///
/// Note that, unlike `parse` and `parseIter`, the first value of `argv` is _not_
/// used as a potential `arg0`.
///
/// It is not possible to precisely deallocate the memory allocated by this function.
/// An `ArenaAllocator` is recommended to prevent memory leaks.
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
            example_required: struct { value: []const u8 },
            example_optional: struct { value: [:0]const u8 = "-" },
            level: struct { value: i32 = -1 },
            flag: struct { value: bool = true },
            @"enum-option": struct { value: enum { auto, always, never } = .auto },
        },
        positional: struct {
            optional: struct { value: ?[]const u8 },
            args: struct { value: []const []const u8 = &.{} },
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
            .example_required = .{ .value = "a.txt" },
            .example_optional = .{ .value = "-" },
            .level = .{ .value = 255 },
            .flag = .{ .value = false },
            .@"enum-option" = .{ .value = .always },
        },
        .positional = .{
            .optional = .{ .value = "positional1" },
            .args = .{ .value = &.{ "positional2", "-12345678", "--positional4", "--positional=5" } },
        },
    }, args);
}

fn innerParseHelp(comptime Args: type, options: Options) error{Help}!noreturn {
    const terminal = options.terminal orelse std.debug.lockStderr(&.{}).terminal();
    defer if (options.terminal == null) std.debug.unlockStderr();
    // Note: arg0 should always be set by public API
    printHelp(Args, terminal.writer, options.arg0.?) catch {};
    if (options.exit) std.process.exit(help_exit_code);
    return error.Help;
}

/// Prints a usage error followed by a usage line.
/// See `getUsageFmt` for more details on the usage line.
/// Unlike `printUsageAndExit`, silently ignores `error.WriteFailed`.
///
/// If `options.exit == false`, returns `error.Usage` instead of exiting.
pub fn usageError(comptime Args: type, options: Options, comptime fmt: []const u8, args: anytype) error{Usage}!noreturn {
    const term = options.terminal orelse std.debug.lockStderr(&.{}).terminal();
    defer if (options.terminal == null) std.debug.unlockStderr();
    print: {
        term.setColor(.red) catch break :print;
        term.writer.writeAll("error") catch break :print;
        term.setColor(.reset) catch break :print;
        term.writer.print(": " ++ fmt ++ "\n", args) catch break :print;
        printUsage(Args, term.writer, options.arg0) catch break :print;
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
    _, const named_fields, const positional_fields = comptime reflectArgs(Args);

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
                            @field(result.named, field.name).value = !@"no-";
                            continue :argparse;
                        }

                        if (@"no-") {
                            if (field.type == .optional) {
                                if (immediate_value) |val| try usageError(Args, options, "unexpected value for argument --no-{s}: {s}", .{
                                    field.name, if (val.len == 0) "''" else val,
                                });

                                @field(result.named, field.name).value = null;
                                continue :argparse;
                            }
                            break;
                        }

                        const arg_value = immediate_value orelse iter.next() orelse try usageError(Args, options, "expected argument after --{s}", .{field.name});
                        const value = try parseValue(Args, gpa, options, field, arg_value);
                        if (field.type == .list) {
                            try @field(named_array_lists, field.name).append(gpa, value);
                        } else {
                            @field(result.named, field.name).value = value;
                        }
                        continue :argparse;
                    }
                }

                // no named arguments match
                try usageError(Args, options, "unrecognized argument: {s}", .{arg});
            }

            if (arg.len >= 2 and arg[0] == '-' and std.ascii.isAlphabetic(arg[1])) {
                shorts: for (arg[1..], 1..) |short, short_i| {
                    if (short == 'h') try innerParseHelp(Args, options);

                    inline for (named_fields, 0..) |field, i| {
                        if (field.info.named.short == short) {
                            named_fields_seen[i] = true;
                            if (field.type == .bool) {
                                @field(result.named, field.name).value = true;
                                continue :shorts;
                            }

                            if (short_i != arg.len - 1) try usageError(Args, options, "expected argument after -{s}", .{&[_]u8{short}});

                            const arg_value = iter.next() orelse try usageError(Args, options, "expected argument after -{s}", .{&[_]u8{short}});
                            const value = try parseValue(Args, gpa, options, field, arg_value);
                            if (field.type == .list) {
                                try @field(named_array_lists, field.name).append(gpa, value);
                            } else {
                                @field(result.named, field.name).value = value;
                            }
                            continue :argparse;
                        }
                    }

                    try usageError(Args, options, "unexpected argument: -{s}", .{&[_]u8{short}});
                }

                continue :argparse;
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
                    @field(result.positional, field.name).value = value;
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
                @field(result.named, field.name).value = default;
            } else {
                try usageError(Args, options, "missing required argument: {s}", .{field.namedFlagUsage()});
            }
        } else if (field.type == .list) {
            @field(result.named, field.name).value = try @field(named_array_lists, field.name).toOwnedSlice(gpa);
        }
    }

    inline for (positional_fields, 0..) |field, i| {
        if (field.type == .list) {
            comptime assert(i == positional_fields.len - 1); // there's only 1 allowed positional list
            var values = try @field(positional_array_lists, field.name).toOwnedSlice(gpa);
            if (values.len == 0 and field.default_value_ptr != null) {
                values = try gpa.dupe(field.type.elemType(), field.defaultValue().?);
            }
            @field(result.positional, field.name).value = values;
        } else if (positional_field_index <= i) {
            if (field.defaultValue()) |default| {
                @field(result.positional, field.name).value = default;
            } else if (field.type == .optional) {
                @field(result.positional, field.name).value = null;
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
        .list, .optional => unreachable, // flattened
    };
}

const ArgType = union(enum) {
    bool,
    @"enum": type,
    float: type,
    int: type,
    string,
    cstring,
    list: List,
    optional: Optional,

    const List = union(enum) {
        int: type,
        float: type,
        string,
        cstring,
        @"enum": type,

        fn of(comptime field_name: []const u8, comptime T: type) List {
            const inner: ArgType = .of(field_name, T);
            return switch (inner) {
                .optional => @compileError("List of optional arguments not supported: " ++ field_name ++ " (" ++ @typeName(T) ++ ")"),
                .list => @compileError("List of list of arguments not supported: " ++ field_name ++ " (" ++ @typeName(T) ++ ")"),
                inline else => |payload, tag| @unionInit(List, @tagName(tag), payload),
            };
        }

        fn getType(comptime elem: List) type {
            return switch (elem) {
                .int, .float, .@"enum" => |Passthru| Passthru,
                .string => []const u8,
                .cstring => [:0]const u8,
            };
        }

        fn toType(comptime elem: List) type {
            return []const elem.getType();
        }

        fn flatten(comptime elem: List) ArgType {
            return switch (elem) {
                inline else => |payload, tag| @unionInit(ArgType, @tagName(tag), payload),
            };
        }
    };

    const Optional = union(enum) {
        @"enum": type,
        float: type,
        int: type,
        string,
        cstring,

        fn of(comptime field_name: []const u8, comptime T: type) Optional {
            const inner: ArgType = .of(field_name, T);
            return switch (inner) {
                .optional => @compileError("Optional optionals are not supported"),
                .list => @compileError("Optional lists are not supported"),
                inline else => |payload, tag| @unionInit(Optional, @tagName(tag), payload),
            };
        }

        fn getType(comptime opt: Optional) type {
            return switch (opt) {
                .@"enum", .int, .float => |Passthru| Passthru,
                .string => []const u8,
                .cstring => [:0]const u8,
            };
        }

        fn toType(comptime opt: Optional) type {
            return ?opt.getType();
        }

        fn flatten(comptime opt: Optional) ArgType {
            return switch (opt) {
                inline else => |payload, tag| @unionInit(ArgType, @tagName(tag), payload),
            };
        }
    };

    fn of(comptime field_name: []const u8, comptime T: type) ArgType {
        return switch (T) {
            bool => .bool,
            []const u8 => .string,
            [:0]const u8 => .cstring,
            else => switch (@typeInfo(T)) {
                .@"enum" => |@"enum"| {
                    if (@"enum".fields.len == 0) @compileError("Empty enums are not allowed: " ++ field_name ++ " (" ++ @typeName(T) ++ ")");
                    return .{ .@"enum" = T };
                },
                .float => .{ .float = T },
                .int => .{ .int = T },
                .pointer => |pointer| {
                    if (pointer.size != .slice) @compileError("Only slice pointers are supported: " ++ field_name ++ " (" ++ @typeName(T) ++ ")");
                    return .{ .list = .of(field_name, pointer.child) };
                },
                .optional => |optional| .{ .optional = .of(field_name, optional.child) },
                else => @compileError("Unsupported argument type: " ++ field_name ++ " (" ++ @typeName(T) ++ ")"),
            },
        };
    }

    /// The type of the field
    fn toType(comptime at: ArgType) type {
        return switch (at) {
            .bool => bool,
            .float, .int, .@"enum" => |Passthru| Passthru,
            .string => []const u8,
            .cstring => [:0]const u8,
            inline .list, .optional => |fwd| fwd.toType(),
        };
    }

    /// The type of arguments being parsed for the field
    fn elemType(comptime at: ArgType) type {
        return switch (at) {
            .bool => bool,
            .float, .int, .@"enum" => |Passthru| Passthru,
            .string => []const u8,
            .cstring => [:0]const u8,
            inline .list, .optional => |fwd| fwd.getType(),
        };
    }

    fn flatten(comptime at: ArgType) ArgType {
        return switch (at) {
            inline .list, .optional => |fwd| fwd.flatten(),
            else => at,
        };
    }
};

const ArgInfo = union(enum) {
    absent,
    named: NamedInfo,
    positional: PositionalInfo,
};

const ArgField = struct {
    name: []const u8,
    type: ArgType,
    default_value_ptr: ?*const anyopaque,
    info: ArgInfo,

    fn namedFlagUsage(comptime field: ArgField) []const u8 {
        const is_optional = field.type == .optional;
        return comptime switch (field.type.flatten()) {
            .bool => if (is_optional) unreachable else "--[no-]" ++ field.name,
            .@"enum" => |Enum| if (is_optional)
                ("--[no-]" ++ field.name ++ "=[(" ++ enumValuesString(Enum) ++ ")]")
            else
                ("--" ++ field.name ++ "=(" ++ enumValuesString(Enum) ++ ")"),
            .float => if (is_optional)
                ("--[no-]" ++ field.name ++ "=[float]")
            else
                ("--" ++ field.name ++ "=float"),
            .int => if (is_optional)
                ("--[no-]" ++ field.name ++ "=[int]")
            else
                ("--" ++ field.name ++ "=int"),
            .string, .cstring => if (is_optional)
                ("--[no-]" ++ field.name ++ "=[string]")
            else
                "--" ++ field.name ++ "=string",
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
        if (@typeInfo(sf.type) != .@"struct" or @typeInfo(sf.type).@"struct".fields.len != 1) @compileError("Arguments must be a `struct { value: <type> }`: " ++ sf.name);

        const value_field = @typeInfo(sf.type).@"struct".fields[0];
        if (!mem.eql(u8, value_field.name, "value")) @compileError("Arguments must be a `struct { value: <type> }`: " ++ sf.name ++ "." ++ value_field.name);

        return .{
            .name = sf.name,
            .type = .of(sf.name, value_field.type),
            .default_value_ptr = value_field.default_value_ptr,
            .info = if (!@hasDecl(sf.type, "info")) .absent else switch (@TypeOf(sf.type.info)) {
                NamedInfo => .{ .named = @field(sf.type, "info") },
                PositionalInfo => .{ .positional = @field(sf.type, "info") },
                else => |T| @compileError("Expected `std.cli.NamedInfo` or `std.cli.PositionalInfo`, got `" ++ @typeName(T) ++ "`: " ++ sf.name),
            },
        };
    }
};

fn reflectArgs(comptime Args: type) struct { Info, []const ArgField, []const ArgField } {
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
    var all_shorts: []const u8 = "";
    inline for (named_fields, 0..) |sf, i| {
        var arg: ArgField = .of(sf);
        switch (arg.info) {
            .named => |named| {
                if (named.short) |short| {
                    // mostly just to make sure that the flag isn't numeric ie `-1` which is common, but will probably get parsed as a float instead
                    if (!std.ascii.isAlphabetic(short)) @compileError("Unsupported short flag '" ++ &[_]u8{short} ++ "': Args.named." ++ sf.name);
                    if (mem.indexOfScalar(u8, all_shorts, short)) |_| @compileError("Short flag '" ++ &[_]u8{short} ++ "' already used: Args.named." ++ sf.name);
                    all_shorts = all_shorts ++ &[_]u8{short};
                }
            },
            .positional => @compileError("Expected `pub const info: std.cli.NamedInfo`, but got PositionalInfo: Args.named." ++ sf.name),
            .absent => arg.info = .{ .named = .{} },
        }
        named_args[i] = arg;
    }

    const positional_fields = if (has_positional) @typeInfo(@FieldType(Args, "positional")).@"struct".fields else &.{};
    var positional_args: [positional_fields.len]ArgField = undefined;
    var has_optionals = false;
    inline for (positional_fields, 0..) |sf, i| {
        var arg: ArgField = .of(sf);
        switch (arg.type) {
            .bool => @compileError("Args.positional cannot have bool fields: " ++ arg.name),
            .list => {
                if (i != positional_fields.len - 1) @compileError("Args.positional may only have a variadic argument as its last argument: Args.positional." ++ arg.name);
            },
            else => {},
        }

        if (arg.defaultValue()) |default| {
            has_optionals = true;
            if (arg.type == .optional and default != null) @compileError("Positional with optional type must have `null` as default, if present: Args.positional." ++ arg.name ++ ": " ++ @typeName(arg.type.toType()) ++ " = " ++ switch (arg.type.flatten()) {
                .@"enum" => @tagName(default),
                .bool => if (default) "true" else "false",
                .float, .int => comptimePrint("{d}", .{default}),
                .cstring, .string => if (default.len == 0) "''" else default,
                .list, .optional => unreachable,
            });
        } else if (has_optionals and arg.type != .list and arg.type != .optional) @compileError("Positional cannot have required arguments after optional arguments: Args.positional." ++ arg.name);

        switch (arg.info) {
            .named => @compileError("Expected `pub const info: std.cli.PositionalInfo`, but got NamedInfo: Args.positional." ++ sf.name),
            .positional => {},
            .absent => arg.info = .{ .positional = .{} },
        }

        positional_args[i] = arg;
    }

    const info: Info = if (@hasDecl(Args, "info")) Args.info else .{};
    return .{ info, &named_args, &positional_args };
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
            const Elem = field.type.list.getType();
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

/// Print the program's usage string to the given writer with the given fallback `arg0` value.
/// If `Args.arg0` is defined, it is used instead.
pub fn printUsage(comptime Args: type, writer: *Io.Writer, arg0: ?[]const u8) Io.Writer.Error!void {
    const usage, const has_arg0_fmt = comptime getUsageFmt(Args);
    if (has_arg0_fmt) {
        try writer.print(usage, .{arg0 orelse "<prog>"});
    } else {
        try writer.writeAll(usage);
    }
}

test printUsage {
    const Args1 = struct {
        pub const info: Info = .{
            .arg0 = "fooprog",
            .description = "my description",
        };

        named: struct {
            foo: struct {
                value: [:0]const u8,
                pub const info: NamedInfo = .{
                    .description = "does a foo thing",
                    .short = 'f',
                };
            },
            bar: struct { value: bool = false },
            baz: struct { value: u8 = 0 },
            quux: struct { value: f32 = -1 },
            quuz: struct { value: i32 },
        },
        positional: struct {
            foo: struct { value: [:0]const u8 },
            bar: struct { value: u32 },
            baz: struct { value: [:0]const u8 = "baz thing" },
            quux: struct { value: []const []const u8 },
        },
    };

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var aw: Writer.Allocating = .init(gpa);
    try printUsage(Args1, &aw.writer, "myprog");
    try testing.expectEqualStrings("Usage: fooprog --foo=string --quuz=int [options...] <foo> <bar> [baz] [quux...]\n", aw.written());
}

/// Returns a generated usage fmt string for the given Args type, and whether a
/// string template for `arg0` is present.
///
/// A string template for `arg0` is only present when `Args.info.arg0` is null.
pub fn getUsageFmt(comptime Args: type) struct { []const u8, bool } {
    return comptime fmt: {
        const info, const named_fields, const positional_fields = reflectArgs(Args);
        if (info.usage) |user_usage| {
            var usage: []const u8 = user_usage;
            if (!mem.endsWith(u8, usage, "\n")) usage = usage ++ "\n";
            if (hasAtLeastOneStringLiteral(usage)) {
                break :fmt if (info.arg0) |arg0|
                    .{ comptimePrint(usage, .{arg0}), false }
                else
                    .{ usage, true };
            } else {
                break :fmt .{ usage, false };
            }
        }

        var usage: []const u8 = "Usage: " ++ (if (info.arg0) |s| s else "{s}");
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
            if (field.default_value_ptr != null or field.type == .list or field.type == .optional) {
                usage = comptimePrint("{s} [{s}{s}]", .{
                    usage, field.name, if (field.type == .list) "..." else "",
                });
            } else {
                usage = comptimePrint("{s} <{s}>", .{
                    usage, field.name,
                });
            }
        }

        break :fmt .{ usage ++ "\n", info.arg0 == null };
    };
}

test getUsageFmt {
    const Args = struct {
        pub const info: Info = .{
            .arg0 = "program",
        };

        named: struct {
            optional: struct { value: bool = false },
            required: struct { value: bool },
        },
        positional: struct {
            required: struct { value: []const u8 },
            optional: struct { value: []const u8 = "" },
            optional2: struct { value: ?[]const u8 },
        },
    };

    const fmt, const hasFmt = getUsageFmt(Args);
    try testing.expect(!hasFmt); // arg0 provided by `Args.arg0`
    try testing.expectEqualStrings(
        \\Usage: program --[no-]required [options...] <required> [optional] [optional2]
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
    try testing.expect(hasAtLeastOneStringLiteral(" {s}{{}}{0s}.  {s}"));
    try testing.expect(hasAtLeastOneStringLiteral("{s}}")); // Note: `print` will throw a compile error for this

    try testing.expect(!hasAtLeastOneStringLiteral(""));
    try testing.expect(!hasAtLeastOneStringLiteral("s"));
    try testing.expect(!hasAtLeastOneStringLiteral("{{s}}"));
    try testing.expect(!hasAtLeastOneStringLiteral("{{s}"));
}

fn escapeFmt(comptime s: []const u8) []const u8 {
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

/// Print the program's help text using the given arg0 fallback.
/// The given arg0 is only used if `Args.arg0` is not defined.
pub fn printHelp(comptime Args: type, writer: *Io.Writer, arg0: ?[]const u8) Io.Writer.Error!void {
    const help, const has_arg0_fmt = comptime getHelpFmt(Args);
    if (has_arg0_fmt)
        try writer.print(help, .{arg0 orelse "<prog>"})
    else
        try writer.writeAll(help);
}

test printHelp {
    const Args = struct {
        pub const info: Info = .{
            .arg0 = "hello",
            .description = "my special description",
            .epilogue = "my special epilogue",
        };

        named: struct {
            foo: struct {
                value: ?[:0]const u8 = null,
                pub const info: NamedInfo = .{
                    .description = "does a foo thing",
                    .short = 'f',
                };
            },
            bar: struct {
                value: ?[]const u8,
                pub const info: NamedInfo = .{
                    .description = "does a bar thing",
                };
            },
            baz: struct { value: u32 = 10 },
            quux: struct { value: i8 = -1 },
            quuz: struct {
                value: f32 = -420,
                pub const info: NamedInfo = .{
                    .description = "Nice.",
                };
            },
            foobar: struct { value: bool = false },
            barfoo: struct { value: bool },
            foobaz: struct { value: []const []const u8 },
            bazfoo: struct { value: ?[]const u8 = null },
        },
        positional: struct {
            foo: struct {
                value: []const u8,
                pub const info: PositionalInfo = .{
                    .description = "a special foo thing",
                };
            },
            bar: struct { value: ?[]const u8 },
            baz: struct {
                value: []const []const u8,
                pub const info: PositionalInfo = .{
                    .description = "not-so-special baz thing",
                };
            },
        },
    };

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var aw: Writer.Allocating = .init(gpa);
    try printHelp(Args, &aw.writer, "myprog");
    try testing.expectEqualStrings(
        \\Usage: hello --[no-]bar=[string] --[no-]barfoo [options...] <foo> [bar] [baz...]
        \\
        \\my special description
        \\
        \\Arguments:
        \\  foo                         [string. required] a special foo thing
        \\  bar                         [string]
        \\  baz...                      [string] not-so-special baz thing
        \\
        \\Options:
        \\  -h, --help                  Print this help text and exit.
        \\  -f, --[no-]foo=[string]     does a foo thing
        \\  --[no-]bar=[string]         [required] does a bar thing
        \\  --baz=int                   [default: 10]
        \\  --quux=int                  [default: -1]
        \\  --quuz=float                [default: -420] Nice.
        \\  --[no-]foobar               [default: no]
        \\  --[no-]barfoo               [required]
        \\  --foobaz=string             [multiple]
        \\  --[no-]bazfoo=[string]
        \\
        \\my special epilogue
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
///
/// {epilogue}
/// ```
///
/// The template has the following caveats:
/// - `{usage}` is the result of `getUsageFmt`
/// - `{description}` is `Args.info.description` if present. Otherwise, this is omitted.
/// - The `Arguments:` section is omitted if `Args.positional` isn't present or is empty.
/// - If a positional arg is a list, `{argname}` has "..." appended and `{default/required}` is omitted.
/// - If `Args.positional.<argname>.info` is omitted, or if `description` field is null, then `{description}` is omitted.
/// - If a named arg is a boolean, `{argname}` is `--[no-]{argname}`, otherwise it's `--{argname}={type}`.
/// - If `Args.named.<argname>.info` is omitted, or if `description` field is null, then `{description}` is omitted
/// - `{epilogue}` is `Args.epilogue` if present. Otherwise, this is omitted.
///
/// Note that string templates in `Args.info.description` and `Args.epilogue` will be assumed to be `arg0`.
pub fn getHelpFmt(comptime Args: type) struct { []const u8, bool } {
    return comptime fmt: {
        const info, const named_fields, const positional_fields = reflectArgs(Args);
        const usage, var has_arg0_fmt = getUsageFmt(Args);
        if (info.help) |user_help| {
            const help: []const u8 = usage ++ "\n" ++ user_help;
            return .{ help, has_arg0_fmt };
        }

        @setEvalBranchQuota(named_fields.len * 1000 + positional_fields.len * 1000);

        var lhs_max_width = 0;

        var arguments_table: [positional_fields.len]struct { []const u8, []const u8 } = undefined;
        for (positional_fields, 0..) |field, i| {
            const lhs: []const u8 = field.name ++ (if (field.type == .list) "..." else "");
            var rhs: []const u8 = comptimePrint("[{s}{s}]", .{
                switch (field.type.flatten()) {
                    .bool, .list, .optional => unreachable,
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
                    .list, .optional => "",
                } else if (field.type == .list or field.type == .optional) "" else ". required",
            });
            if (field.info.positional.description) |description| {
                rhs = rhs ++ " " ++ @as([]const u8, if (has_arg0_fmt) escapeFmt(description) else description);
            }

            arguments_table[i] = .{ lhs, rhs };
            lhs_max_width = @max(lhs_max_width, lhs.len);
        }

        var options_table: [named_fields.len + 1]struct { []const u8, []const u8 } = undefined;
        options_table[0] = .{ "-h, --help", "Print this help text and exit." };
        lhs_max_width = @max(lhs_max_width, "--help".len);

        for (named_fields, 1..) |field, i| {
            var lhs: []const u8 = if (field.info.named.short) |short|
                ("-" ++ &[_]u8{short} ++ ", ")
            else
                "";
            lhs = lhs ++ field.namedFlagUsage();
            var rhs: []const u8 = switch (field.type) {
                .bool => if (field.defaultValue()) |default| comptimePrint("[default: {s}] ", .{if (default) "yes" else "no"}) else "[required] ",
                .@"enum" => if (field.defaultValue()) |default| comptimePrint("[default: {t}] ", .{default}) else "[required] ",
                .float, .int => if (field.defaultValue()) |default| comptimePrint("[default: {d}] ", .{default}) else "[required] ",
                .cstring, .string => if (field.defaultValue()) |default| comptimePrint("[default: {s}] ", .{if (default.len == 0) "''" else default}) else "[required] ",
                .optional => |inner| default: {
                    if (field.defaultValue()) |default_optional| {
                        if (default_optional) |default| switch (inner) {
                            .@"enum" => break :default comptimePrint("[default: {t}] ", .{default}),
                            .float, .int => break :default comptimePrint("[default: {d}] ", .{default}),
                            .cstring, .string => break :default comptimePrint("[default: {s}] ", .{default}),
                            .list => break :default "[multiple] ",
                            else => {},
                        };
                        break :default "";
                    } else {
                        break :default "[required] ";
                    }
                },
                .list => "[multiple] ",
            };

            if (field.info.named.description) |description| {
                rhs = rhs ++ @as([]const u8, if (has_arg0_fmt) escapeFmt(description) else description);
            }

            rhs = mem.trimEnd(u8, rhs, " \n");
            options_table[i] = .{ lhs, rhs };
            lhs_max_width = @max(lhs_max_width, lhs.len);
        }

        var help: []const u8 = usage;
        if (info.description) |description| {
            help = help ++ "\n";
            if (hasAtLeastOneStringLiteral(description)) {
                if (info.arg0) |arg0| {
                    help = help ++ comptimePrint(description, .{arg0});
                } else {
                    has_arg0_fmt = true;
                    help = help ++ description;
                }
            } else {
                help = help ++ description;
            }
            help = help ++ "\n";
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
            help = help ++ "  " ++ lhs;
            if (rhs.len != 0) {
                const middle_spacing = " " ** (lhs_max_width - lhs.len);
                help = help ++ middle_spacing ++ rhs;
            }
            help = help ++ "\n";
        }

        if (info.epilogue) |epilogue| {
            help = help ++ "\n";
            if (hasAtLeastOneStringLiteral(epilogue)) {
                if (info.arg0) |arg0| {
                    help = help ++ comptimePrint(epilogue, .{arg0});
                } else {
                    has_arg0_fmt = true;
                    help = help ++ epilogue;
                }
            } else {
                help = help ++ epilogue;
            }
            help = help ++ "\n";
        }

        break :fmt .{ help, has_arg0_fmt };
    };
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
            b: struct { value: bool },
        },
    };

    try testing.expectEqualDeep(Args{ .named = .{ .b = .{ .value = true } } }, try parseSlice(Args, allocator, &[_][]const u8{"--b"}, .{}));
    try testing.expectEqualDeep(Args{ .named = .{ .b = .{ .value = false } } }, try parseSlice(Args, allocator, &[_][]const u8{"--no-b"}, .{}));
    try testing.expectEqualDeep(Args{ .named = .{ .b = .{ .value = true } } }, try parseSlice(Args, allocator, &[_][]const u8{ "--no-b", "--b" }, .{}));
    try testing.expectEqualDeep(Args{ .named = .{ .b = .{ .value = false } } }, try parseSlice(Args, allocator, &[_][]const u8{ "--b", "--no-b" }, .{}));

    try testing.expectError(error.Usage, parseSlice(Args, allocator, &[_][]const u8{"--b=true"}, silent_options));
    try testing.expectError(error.Usage, parseSlice(Args, allocator, &[_][]const u8{"--b=false"}, silent_options));
}

test "string" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            a: struct { value: []const u8 },
            b: struct { value: [:0]const u8 },
        },
    };
    const args = try parseSlice(Args, allocator, &[_][:0]const u8{
        "--a", "a",
        "--b", "b",
    }, .{});

    try testing.expectEqualDeep(Args{
        .named = .{
            .a = .{ .value = "a" },
            .b = .{ .value = "b" },
        },
    }, args);
}

test "ints and floats" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // https://codeberg.org/ziglang/zig/issues/31036

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            int_u32: struct { value: u32 },
            int_i32: struct { value: i32 },
            int_u8: struct { value: u8 },
            int_u256: struct { value: u256 },
            float_f32: struct { value: f32 },
            float_f64: struct { value: f64 },
            inf_f32: struct { value: f32 },
            ninf_f64: struct { value: f64 },
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
            .int_u32 = .{ .value = 0xffffffff },
            .int_i32 = .{ .value = -0x80000000 },
            .int_u8 = .{ .value = 0o310 },
            .int_u256 = .{ .value = 115792089237316195423570985008687907853269984665640564039457584007913129639935 },
            .float_f32 = .{ .value = 1.25 },
            .float_f64 = .{ .value = -0xab.cdef012345p-12 },
            .inf_f32 = .{ .value = std.math.inf(f32) },
            .ninf_f64 = .{ .value = -std.math.inf(f64) },
        },
    }, args);

    const Args2 = struct {
        named: struct {
            nan: struct { value: f64 },
        },
    };
    const args2 = try parseSlice(Args2, allocator, &[_][]const u8{
        "--nan", "nAN",
    }, .{});

    try testing.expect(std.math.isNan(args2.named.nan.value));
}

test "array" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            path: struct { value: []const []const u8 = &.{} },
            id: struct { value: []const i32 = &.{} },
        },
        positional: struct {
            args: struct { value: []const []const u8 = &.{} },
        },
    };

    try testing.expectEqualDeep(Args{
        .named = .{
            .path = .{ .value = &[_][]const u8{ "a", "b", "a" } },
            .id = .{ .value = &[_]i32{ 1, -12 } },
        },
        .positional = .{
            .args = .{ .value = &[_][]const u8{ "x", "y" } },
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
            color: struct { value: enum {
                always,
                never,
                auto,
            } },
            guess: struct { value: enum {
                @"the-only-option",
            } },
            signal: struct { value: enum(u8) {
                KILL = 9,
                TERM = 15,
                VTALRM = 26,
            } },
        },
    };
    const args = try parseSlice(Args, allocator, &[_][]const u8{
        "--color",  "always",
        "--guess",  "the-only-option",
        "--signal", "TERM",
    }, .{});

    try testing.expectEqualDeep(Args{
        .named = .{
            .color = .{ .value = .always },
            .guess = .{ .value = .@"the-only-option" },
            .signal = .{ .value = .TERM },
        },
    }, args);
}

test "defaults" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const Args = struct {
        named: struct {
            level: struct { value: i8 = -1 } = .{},
            ratio: struct { value: f32 = 0.5 } = .{},
            path: struct { value: []const u8 = "-" } = .{},
            color: struct { value: enum { always, never, auto } = .auto } = .{},
            file: struct { value: []const []const u8 = &.{} } = .{},
            force: struct { value: bool = false } = .{},
            cleanup: struct { value: bool = true } = .{},
        },
    };

    try testing.expectEqualDeep(Args{
        .named = .{},
    }, try parseSlice(Args, allocator, &[_][]const u8{}, .{}));
    try testing.expectEqualDeep(Args{
        .named = .{
            .color = .{ .value = .always },
        },
    }, try parseSlice(Args, allocator, &[_][]const u8{ "--color", "always" }, .{}));
    try testing.expectEqualDeep(Args{
        .named = .{
            .file = .{ .value = &[_][]const u8{"file.txt"} },
        },
    }, try parseSlice(Args, allocator, &[_][]const u8{ "--file", "file.txt" }, .{}));

    try testing.expectEqualDeep(Args{
        .named = .{
            .force = .{ .value = true },
            .cleanup = .{ .value = false },
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
                level: struct { value: i8 = -1 } = .{},
                ratio: struct { value: f32 = 0.5 } = .{},
                path: struct { value: []const u8 = "-" } = .{},
                color: struct { value: enum { always, never, auto } = .auto } = .{},
                file: struct { value: []const []const u8 = &.{} } = .{},
            },
        };

        try testing.expectEqualDeep(Args{
            .positional = .{},
        }, try parseSlice(Args, allocator, &[_][]const u8{}, .{}));
        try testing.expectEqualDeep(Args{
            .positional = .{
                .level = .{ .value = 1 },
                .ratio = .{ .value = 2 },
                .path = .{ .value = "a.txt" },
                .color = .{ .value = .always },
                .file = .{ .value = &[_][]const u8{ "file1", "file2" } },
            },
        }, try parseSlice(Args, allocator, &[_][]const u8{ "1", "2", "a.txt", "always", "file1", "file2" }, .{}));
    }

    // required
    {
        const Args = struct {
            positional: struct {
                level: struct { value: i8 },
                ratio: struct { value: f32 },
                path: struct { value: []const u8 },
                color: struct { value: enum { always, never, auto } },
                file: struct { value: []const []const u8 = &.{} } = .{},
            },
        };

        try testing.expectError(error.Usage, parseSlice(Args, allocator, &[_][]const u8{}, silent_options));
        try testing.expectError(error.Usage, parseSlice(Args, allocator, &[_][]const u8{ "1", "2", "a.txt" }, silent_options));
        try testing.expectEqualDeep(Args{
            .positional = .{
                .level = .{ .value = 1 },
                .ratio = .{ .value = 2 },
                .path = .{ .value = "a.txt" },
                .color = .{ .value = .always },
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
            name: struct { value: []const u8 = "" },
        },
    }, allocator, &[_][]const u8{"--bogus"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--bogus") != null);

    // expected argument
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: []const u8 = "" },
        },
    }, allocator, &[_][]const u8{"--name"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // --no-<name> for non-bool.
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: []const u8 = "" },
        },
    }, allocator, &[_][]const u8{"--no-name"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--no-name") != null);

    // --name=false for bool
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: bool = false },
        },
    }, allocator, &[_][]const u8{"--name=true"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // missing required argument
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: []const u8 },
        },
    }, allocator, &[_][]const u8{}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // parse int error
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: i32 },
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: []const i32 = &.{} },
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // parse float error
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: f32 },
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: []const f32 = &.{} },
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);

    // parse enum error
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            name: struct { value: enum { auto, never, always } },
        },
    }, allocator, &[_][]const u8{"--name=abc"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "--name") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "abc") != null);
    // Error should suggest the set of options.
    try testing.expect(mem.indexOf(u8, aw.written(), "always") != null);

    // single-letter argument doesn't apply to similarly-named named argument
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        named: struct {
            z: struct { value: bool = false },
        },
        positional: struct {
            args: struct { value: []const []const u8 = &.{} },
        },
    }, allocator, &[_][]const u8{"-z"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "-z") != null);

    // expected required positional argument
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        positional: struct {
            input_file: struct { value: []const u8 },
        },
    }, allocator, &[_][]const u8{}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "input_file") != null);
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        positional: struct {
            input_file: struct { value: []const u8 },
            output_file: struct { value: []const u8 = "" },
        },
    }, allocator, &[_][]const u8{}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "input_file") != null);
    aw.clearRetainingCapacity();
    try testing.expectError(error.Usage, parseSlice(struct {
        positional: struct {
            input_file: struct { value: []const u8 },
            output_file: struct { value: []const u8 },
            other: struct { value: []const u8 = "" },
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
            str: struct { value: []const u8 },
            int: struct { value: i32 },
            flag: struct { value: bool },
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
            color: struct { value: enum { never, auto, always } = .auto },
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
            name: struct { value: []const u8 },
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const scalar_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            name: struct { value: []const []const u8 = &.{} },
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    try testing.expect(!mem.eql(u8, scalar_help, aw.written()));

    // Default values should be rendered somehow.
    aw.clearRetainingCapacity();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            str: struct { value: []const u8 = "hello" },
            int: struct { value: i32 = 3 },
            f: struct { value: f32 = 1.25 },
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), "hello") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "3") != null);
    try testing.expect(mem.indexOf(u8, aw.written(), "1.25") != null);

    // Test that bool arguments express the default somehow.
    aw.clearRetainingCapacity();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            b: struct { value: bool },
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const bool_required_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            b: struct { value: bool = true },
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const default_true_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            b: struct { value: bool = false },
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
            color: struct { value: enum { never, auto, always } },
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const enum_required_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            color: struct { value: enum { never, auto, always } = .auto },
        },
    }, allocator, &[_][]const u8{"--help"}, options));
    const default_auto_help = try aw.toOwnedSlice();
    try testing.expectError(error.Help, parseSlice(struct {
        named: struct {
            color: struct { value: enum { never, auto, always } = .never },
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
            str_arr: struct { value: []const []const u8 = &.{} } = .{},
            int_arr: struct { value: []const i32 = &.{} } = .{},
            empty_arr: struct { value: []const []const u8 = &.{} } = .{},
        },
        positional: struct {
            args: struct { value: []const []const u8 = &.{} } = .{},
        },
    };

    const args = try parseSlice(Args, testing.allocator, &[_][]const u8{
        "--str_arr=hello1", "--str_arr", "hello2",
        "--int_arr=123456", "--int_arr", "789012",
        "positional-12345", "--",        "positi",
    }, .{});

    try testing.expectEqualDeep(Args{
        .named = .{
            .str_arr = .{ .value = &.{ "hello1", "hello2" } },
            .int_arr = .{ .value = &.{ 123456, 789012 } },
        },
        .positional = .{
            .args = .{ .value = &.{ "positional-12345", "positi" } },
        },
    }, args);

    // Surgically cleanup memory.
    testing.allocator.free(args.named.str_arr.value);
    testing.allocator.free(args.named.int_arr.value);
    testing.allocator.free(args.named.empty_arr.value);
    testing.allocator.free(args.positional.args.value);
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
        pub const info: Info = .{
            .usage = "Usage: the-zip-thing --output path [options] input.zip",
            .help =
            \\Arguments:
            \\  --output path     where to write the output stuff
            \\  --[no-]force      overwrite output if already exists
            \\  input.zip         the zip file to read
            \\  --help            print this help and exit
            \\
            ,
        };
        named: struct {
            output: struct { value: []const u8 },
            force: struct { value: bool = false },
        },
        positional: struct {
            args: struct { value: []const []const u8 = &.{} },
        },
    };
    try testing.expectError(error.Help, parseSlice(Args, allocator, &[_][]const u8{"--help"}, options));
    try testing.expectEqualStrings(Args.info.usage.? ++ "\n\n" ++ Args.info.help.?, aw.written());
}

test "description" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var aw: Writer.Allocating = .init(allocator);
    const term: Io.Terminal = .{ .mode = .no_color, .writer = &aw.writer };
    const options = Options{ .arg0 = "unused-prog", .terminal = term, .exit = false };

    const Args = struct {
        pub const info: Info = .{
            .description = "This is a description",
        };
    };
    try testing.expectError(error.Help, parseSlice(Args, allocator, &[_][]const u8{"--help"}, options));
    try testing.expect(mem.indexOf(u8, aw.written(), Args.info.description.?) != null);
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
            output: struct {
                value: []const u8,
                pub const info: NamedInfo = .{
                    .description = "help for output",
                };
            },
        },
        positional: struct {
            args: struct {
                value: []const []const u8 = &.{},
                pub const info: PositionalInfo = .{
                    .description = "help for args",
                };
            },
        },
    };
    try testing.expectError(error.Help, parseSlice(Args, allocator, &[_][]const u8{"--help"}, options));
    try testing.expect(null != mem.indexOf(u8, aw.written(), @FieldType(@FieldType(Args, "named"), "output").info.description.?));
    try testing.expect(null != mem.indexOf(u8, aw.written(), @FieldType(@FieldType(Args, "positional"), "args").info.description.?));
}

test "optionals" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const options: Options = .{ .arg0 = "unused-prog", .terminal = failing_terminal, .exit = false };

    const Args = struct {
        named: struct {
            foo: struct { value: ?[]const u8 = null },
            bar: struct { value: ?[]const u8 },
        },
        positional: struct {
            opt1: struct { value: ?[]const u8 },
            opt2: struct { value: ?[]const u8 = null },
            splat: struct { value: []const []const u8 },
        },
    };

    const args = try parseSlice(Args, allocator, &[_][]const u8{
        "--bar=hi", "--no-bar",
        "--bar",    "hello",
    }, options);
    try testing.expectEqualDeep(Args{
        .named = .{
            .foo = .{},
            .bar = .{ .value = "hello" },
        },
        .positional = .{
            .opt1 = .{ .value = null },
            .opt2 = .{},
            .splat = .{ .value = &.{} },
        },
    }, args);
}

test "shorts" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var aw: Writer.Allocating = .init(allocator);
    const term: Io.Terminal = .{ .mode = .no_color, .writer = &aw.writer };
    const options: Options = .{ .arg0 = "unused-prog", .terminal = term, .exit = false };
    errdefer std.debug.print("{s}", .{aw.written()});

    const Args = struct {
        named: struct {
            foo: struct {
                value: ?[]const u8 = null,
                pub const info: NamedInfo = .{
                    .short = 'f',
                };
            },
            bar: struct {
                value: bool = false,
                pub const info: NamedInfo = .{
                    .short = 'b',
                };
            },
            quux: struct {
                value: bool = true,
                pub const info: NamedInfo = .{
                    .short = 'Q',
                };
            },
        },
    };

    const args1 = try parseSlice(Args, allocator, &[_][]const u8{
        "-f",  "foo",
        "-Qb",
    }, options);
    try testing.expectEqualDeep(Args{
        .named = .{
            .foo = .{ .value = "foo" },
            .bar = .{ .value = true },
            .quux = .{},
        },
    }, args1);

    const args2 = try parseSlice(Args, allocator, &[_][]const u8{
        "-Qf", "bar",
    }, options);
    try testing.expectEqualDeep(Args{
        .named = .{
            .foo = .{ .value = "bar" },
            .bar = .{},
            .quux = .{},
        },
    }, args2);
}

test "module documentation example" {
    const Args = struct {
        pub const info: std.cli.Info = .{
            .arg0 = "myprog",
            .description = "this program does a thing",
            .epilogue = "example: myprog --output o.txt hello.txt",
        };

        named: struct {
            verbose: struct { value: bool = false },
            output: struct {
                value: [:0]const u8,
                pub const info: std.cli.NamedInfo = .{
                    .description = "path to output file",
                    .short = 'o',
                };
            },
        },
        positional: struct {
            input: struct {
                value: []const u8,
                pub const info: std.cli.PositionalInfo = .{
                    .description = "path to input file",
                };
            },
            args: struct { value: []const []const u8 = &.{} },
        },
    };

    var arena_allocator: ArenaAllocator = .init(std.testing.allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const options: Options = .{ .exit = false };

    const args = try parseSlice(
        Args,
        arena,
        &[_][]const u8{ "--output", "o.txt", "hello.txt" },
        options,
    );
    try std.testing.expectEqualDeep(Args{
        .named = .{
            .verbose = .{},
            .output = .{ .value = "o.txt" },
        },
        .positional = .{
            .input = .{ .value = "hello.txt" },
            .args = .{},
        },
    }, args);

    var aw: Writer.Allocating = .init(arena);
    try printHelp(Args, &aw.writer, null);
    try std.testing.expectEqualStrings(
        \\Usage: myprog --output=string [options...] <input> [args...]
        \\
        \\this program does a thing
        \\
        \\Arguments:
        \\  input                   [string. required] path to input file
        \\  args...                 [string]
        \\
        \\Options:
        \\  -h, --help              Print this help text and exit.
        \\  --[no-]verbose          [default: no]
        \\  -o, --output=string     [required] path to output file
        \\
        \\example: myprog --output o.txt hello.txt
        \\
    , aw.written());
}
