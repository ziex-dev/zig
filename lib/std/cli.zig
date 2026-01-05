const std = @import("std");
const fmt = std.fmt;
const Args = std.process.Args;

pub const Error = error{
    MissingValue,
    InvalidValue,
    UnknownFlag,
};

pub fn parse(comptime T: type, args: *Args.Iterator) Error!T {
    return switch (@typeInfo(T)) {
        .@"struct" => parseStruct(T, args),
        .@"union" => parseUnion(T, args),
        else => parseSimple(T, args),
    };
}

fn parseStruct(comptime T: type, args: *Args.Iterator) Error!T {
    _ = args; // autofix
    return .{};
}

fn parseUnion(comptime T: type, args: *Args.Iterator) Error!T {
    _ = args; // autofix
    return .{};
}

fn parseSimple(comptime T: type, args: *Args.Iterator) Error!T {
    const arg = args.next() orelse return Error.MissingValue;

    const value = switch (@typeInfo(T)) {
        .int => |int| switch (int.signedness) {
            .signed => fmt.parseInt(T, arg, 0),
            .unsigned => fmt.parseUnsigned(T, arg, 0),
        },
        .float => fmt.parseFloat(T, arg),
        inline else => @compileError("Unsupported type for simple parsing: " ++ @typeName(T)),
    } catch Error.InvalidValue;

    return value;
}

test "std.cli: values" {
    var args: Args = .{
        .vector = &[_][*:0]const u8{"42"},
    };

    var it = args.iterate();
    const parsed = try parse(u32, &it);
    try std.testing.expect(parsed == 42);
}
