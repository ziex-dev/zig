const std = @import("std");
const ascii = std.ascii;

/// Returns the number of characters in the identifier if it were in
/// snake case.
pub fn getSnakeCaseLength(identifier: []const u8) !usize {
    return computeLength(identifier, .delimited);
}

test getSnakeCaseLength {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqual(8, try getSnakeCaseLength(identifier));
    }
}

/// Converts an identifier to snake case, using the provided buffer to
/// write the result to, while returning the actual number of elements
/// written to.
pub fn toSnakeCaseBuffer(identifier: []const u8, buffer: []u8) !usize {
    var it: SegmentIterator = try .init(identifier);

    var offset: usize = 0;
    var maybe_segment = try it.next();
    while (maybe_segment) |segment| {
        for (segment, 0..) |char, i| {
            if (offset + i >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset + i] = ascii.toLower(char);
        }

        offset += segment.len;
        maybe_segment = try it.next();
        if (maybe_segment != null) {
            if (offset >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset] = '_';
            offset += 1;
        }
    }

    return offset;
}

test toSnakeCaseBuffer {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        const buffer = try std.testing.allocator.alloc(u8, try getSnakeCaseLength(identifier));
        defer std.testing.allocator.free(buffer);

        try std.testing.expectEqual(8, try toSnakeCaseBuffer(identifier, buffer));
        try std.testing.expectEqualStrings("foo1_bar", buffer);
    }
}

/// Converts an identifier to snake case at compile-time, returning
/// a constant string.
pub fn toSnakeCase(comptime identifier: []const u8) return_type: {
    const length = getSnakeCaseLength(identifier) catch @compileError("invalid identifier: {s}" ++ identifier);
    break :return_type *const [length:0]u8;
} {
    const static = struct {
        const length = getSnakeCaseLength(identifier) catch unreachable;
        const inflected: [length:0]u8 = make_inflected: {
            var buffer: [length:0]u8 = undefined;
            _ = toSnakeCaseBuffer(identifier, &buffer) catch unreachable;
            break :make_inflected buffer;
        };
    };

    return &static.inflected;
}

test toSnakeCase {
    inline for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqualStrings("foo1_bar", comptime toSnakeCase(identifier));
    }
}

/// Returns the number of characters in the identifier if it were in
/// pascal case.
pub fn getPascalCaseLength(identifier: []const u8) !usize {
    return computeLength(identifier, .undelimited);
}

test getPascalCaseLength {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqual(7, try getPascalCaseLength(identifier));
    }
}

/// Converts an identifier to pascal case, using the provided buffer
/// to write the result to, while returning the actual number of
/// elements written to.
pub fn toPascalCaseBuffer(identifier: []const u8, buffer: []u8) !usize {
    var it: SegmentIterator = try .init(identifier);

    var offset: usize = 0;
    var maybe_segment = try it.next();
    while (maybe_segment) |segment| : (maybe_segment = try it.next()) {
        for (segment, 0..) |char, i| {
            if (offset + i >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset + i] = if (i == 0)
                ascii.toUpper(char)
            else
                ascii.toLower(char);
        }

        offset += segment.len;
    }

    return offset;
}

test toPascalCaseBuffer {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        const buffer = try std.testing.allocator.alloc(u8, try getPascalCaseLength(identifier));
        defer std.testing.allocator.free(buffer);

        try std.testing.expectEqual(7, try toPascalCaseBuffer(identifier, buffer));
        try std.testing.expectEqualStrings("Foo1Bar", buffer);
    }
}

/// Converts an identifier to snake case at compile-time, returning
/// a constant string.
pub fn toPascalCase(comptime identifier: []const u8) return_type: {
    const length = getPascalCaseLength(identifier) catch @compileError("invalid identifier: {s}" ++ identifier);
    break :return_type *const [length:0]u8;
} {
    const static = struct {
        const length = getPascalCaseLength(identifier) catch unreachable;
        const inflected: [length:0]u8 = make_inflected: {
            var buffer: [length:0]u8 = undefined;
            _ = toPascalCaseBuffer(identifier, &buffer) catch unreachable;
            break :make_inflected buffer;
        };
    };

    return &static.inflected;
}

test toPascalCase {
    inline for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqualStrings("Foo1Bar", comptime toPascalCase(identifier));
    }
}

/// Returns the number of characters in the identifier if it were in
/// camel case.
pub fn getCamelCaseLength(identifier: []const u8) !usize {
    return computeLength(identifier, .undelimited);
}

test getCamelCaseLength {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqual(7, try getCamelCaseLength(identifier));
    }
}

/// Converts an identifier to camel case, using the provided buffer to
/// write the result to, while returning the actual number of elements
/// written to.
pub fn toCamelCaseBuffer(identifier: []const u8, buffer: []u8) !usize {
    var it: SegmentIterator = try .init(identifier);

    var offset: usize = 0;
    var maybe_segment = try it.next();
    var first_segment: bool = true;
    while (maybe_segment) |segment| : (maybe_segment = try it.next()) {
        for (segment, 0..) |char, i| {
            if (offset + i >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset + i] = if (!first_segment and i == 0)
                ascii.toUpper(char)
            else
                ascii.toLower(char);

            first_segment = false;
        }

        offset += segment.len;
    }

    return offset;
}

test toCamelCaseBuffer {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        const buffer = try std.testing.allocator.alloc(u8, try getCamelCaseLength(identifier));
        defer std.testing.allocator.free(buffer);

        try std.testing.expectEqual(7, try toCamelCaseBuffer(identifier, buffer));
        try std.testing.expectEqualStrings("foo1Bar", buffer);
    }
}

/// Converts an identifier to snake case at compile-time, returning
/// a constant string.
pub fn toCamelCase(comptime identifier: []const u8) return_type: {
    const length = getCamelCaseLength(identifier) catch @compileError("invalid identifier: {s}" ++ identifier);
    break :return_type *const [length:0]u8;
} {
    const static = struct {
        const length = getCamelCaseLength(identifier) catch unreachable;
        const inflected: [length:0]u8 = make_inflected: {
            var buffer: [length:0]u8 = undefined;
            _ = toCamelCaseBuffer(identifier, &buffer) catch unreachable;
            break :make_inflected buffer;
        };
    };

    return &static.inflected;
}

test toCamelCase {
    inline for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqualStrings("Foo1Bar", comptime toPascalCase(identifier));
    }
}

/// Returns the number of characters in the identifier if it were in
/// snake case.
pub fn getUpcaseCaseLength(identifier: []const u8) !usize {
    return computeLength(identifier, .delimited);
}

test getUpcaseCaseLength {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqual(8, try getUpcaseCaseLength(identifier));
    }
}

/// Converts an identifier to upcase case, using the provided buffer
/// to write the result to, while returning the actual number of
/// elements written to.
pub fn toUpcaseCaseBuffer(identifier: []const u8, buffer: []u8) !usize {
    var it: SegmentIterator = try .init(identifier);

    var offset: usize = 0;
    var maybe_segment = try it.next();
    while (maybe_segment) |segment| {
        for (segment, 0..) |char, i| {
            if (offset + i >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset + i] = ascii.toUpper(char);
        }

        offset += segment.len;
        maybe_segment = try it.next();
        if (maybe_segment != null) {
            if (offset >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset] = '_';
            offset += 1;
        }
    }

    return offset;
}

test toUpcaseCaseBuffer {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        const buffer = try std.testing.allocator.alloc(u8, try getSnakeCaseLength(identifier));
        defer std.testing.allocator.free(buffer);

        try std.testing.expectEqual(8, try toSnakeCaseBuffer(identifier, buffer));
        try std.testing.expectEqualStrings("foo1_bar", buffer);
    }
}

/// Converts an identifier to upcase case at compile-time, returning
/// a constant string.
pub fn toUpcaseCase(comptime identifier: []const u8) return_type: {
    const length = getUpcaseCaseLength(identifier) catch @compileError("invalid identifier: {s}" ++ identifier);
    break :return_type *const [length:0]u8;
} {
    const static = struct {
        const length = getUpcaseCaseLength(identifier) catch unreachable;
        const inflected: [length:0]u8 = make_inflected: {
            var buffer: [length:0]u8 = undefined;
            _ = toUpcaseCaseBuffer(identifier, &buffer) catch unreachable;
            break :make_inflected buffer;
        };
    };

    return &static.inflected;
}

test toUpcaseCase {
    inline for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqualStrings("FOO1_BAR", comptime toUpcaseCase(identifier));
    }
}

/// Returns the number of characters in the identifier if it were in
/// kebab case.
pub fn getKebabCaseLength(identifier: []const u8) !usize {
    return computeLength(identifier, .delimited);
}

test getKebabCaseLength {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqual(8, try getKebabCaseLength(identifier));
    }
}

/// Converts an identifier to kebab case, using the provided buffer to
/// write the result to, while returning the actual number of elements
/// written to.
pub fn toKebabCaseBuffer(identifier: []const u8, buffer: []u8) !usize {
    var it: SegmentIterator = try .init(identifier);

    var offset: usize = 0;
    var maybe_segment = try it.next();
    while (maybe_segment) |segment| {
        for (segment, 0..) |char, i| {
            if (offset + i >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset + i] = ascii.toLower(char);
        }

        offset += segment.len;
        maybe_segment = try it.next();
        if (maybe_segment != null) {
            if (offset >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset] = '-';
            offset += 1;
        }
    }

    return offset;
}

test toKebabCaseBuffer {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        const buffer = try std.testing.allocator.alloc(u8, try getSnakeCaseLength(identifier));
        defer std.testing.allocator.free(buffer);

        try std.testing.expectEqual(8, try toKebabCaseBuffer(identifier, buffer));
        try std.testing.expectEqualStrings("foo1-bar", buffer);
    }
}

/// Converts an identifier to kebab case at compile-time, returning
/// a constant string.
pub fn toKebabCase(comptime identifier: []const u8) return_type: {
    const length = getKebabCaseLength(identifier) catch @compileError("invalid identifier: {s}" ++ identifier);
    break :return_type *const [length:0]u8;
} {
    const static = struct {
        const length = getKebabCaseLength(identifier) catch unreachable;
        const inflected: [length:0]u8 = make_inflected: {
            var buffer: [length:0]u8 = undefined;
            _ = toKebabCaseBuffer(identifier, &buffer) catch unreachable;
            break :make_inflected buffer;
        };
    };

    return &static.inflected;
}

test toKebabCase {
    inline for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqualStrings("foo1-bar", comptime toKebabCase(identifier));
    }
}

/// Returns the number of characters in the identifier if it were in
/// capital case.
pub fn getCapitalCaseLength(identifier: []const u8) !usize {
    return computeLength(identifier, .delimited);
}

test getCapitalCaseLength {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqual(8, try getCapitalCaseLength(identifier));
    }
}

/// Converts an identifier to capital case, using the provided buffer
/// to write the result to, while returning the actual number of
/// elements written to.
pub fn toCapitalCaseBuffer(identifier: []const u8, buffer: []u8) !usize {
    var it: SegmentIterator = try .init(identifier);

    var offset: usize = 0;
    var maybe_segment = try it.next();
    while (maybe_segment) |segment| {
        for (segment, 0..) |char, i| {
            if (offset + i >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset + i] = if (i == 0)
                ascii.toUpper(char)
            else
                ascii.toLower(char);
        }

        offset += segment.len;
        maybe_segment = try it.next();
        if (maybe_segment != null) {
            if (offset >= buffer.len) {
                return error.Overflow;
            }

            buffer[offset] = '_';
            offset += 1;
        }
    }

    return offset;
}

test toCapitalCaseBuffer {
    for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        const buffer = try std.testing.allocator.alloc(u8, try getCapitalCaseLength(identifier));
        defer std.testing.allocator.free(buffer);

        try std.testing.expectEqual(8, try toCapitalCaseBuffer(identifier, buffer));
        try std.testing.expectEqualStrings("Foo1_Bar", buffer);
    }
}

/// Converts an identifier to capital case at compile-time, returning
/// a constant string.
pub fn toCapitalCase(comptime identifier: []const u8) return_type: {
    const length = getCapitalCaseLength(identifier) catch @compileError("invalid identifier: {s}" ++ identifier);
    break :return_type *const [length:0]u8;
} {
    const static = struct {
        const length = getCapitalCaseLength(identifier) catch unreachable;
        const inflected: [length:0]u8 = make_inflected: {
            var buffer: [length:0]u8 = undefined;
            _ = toCapitalCaseBuffer(identifier, &buffer) catch unreachable;
            break :make_inflected buffer;
        };
    };

    return &static.inflected;
}

test toCapitalCase {
    inline for ([_][]const u8{
        "foo1_bar",
        "FOO1_BAR",
        "foo1-bar",
        "foo1__bar",
        "Foo1Bar",
        "FOO1Bar",
        "FOO1_BAR",
    }) |identifier| {
        try std.testing.expectEqualStrings("Foo1_Bar", comptime toCapitalCase(identifier));
    }
}

const ComputeLengthMode = enum {
    delimited,
    undelimited,
};

fn computeLength(identifier: []const u8, mode: ComputeLengthMode) !usize {
    var num_chars: usize = 0;
    var num_segments: usize = 0;

    var it: SegmentIterator = try .init(identifier);
    while (try it.next()) |segment| {
        num_chars += segment.len;
        num_segments += 1;
    }

    return num_chars + switch (mode) {
        .delimited => num_segments - 1,
        .undelimited => 0,
    };
}

const SegmentIterator = struct {
    const Error = error{
        InvalidIdentifier,
    };

    identifier: []const u8,
    offset: usize = 0,

    pub fn init(identifier: []const u8) Error!SegmentIterator {
        if (identifier.len <= 0) {
            return Error.InvalidIdentifier;
        }

        if (!ascii.isAlphabetic(identifier[0])) {
            return Error.InvalidIdentifier;
        }

        return .{ .identifier = identifier };
    }

    pub fn next(it: *SegmentIterator) Error!?[]const u8 {
        var char = try it.advance() orelse return null;

        while (char == '-' or char == '_') {
            char = try it.advance() orelse return null;
        }

        const start = it.offset - 1;

        if (ascii.isLower(char)) {
            char = try it.advance() orelse return it.identifier[start..];
            while (char != '_' and char != '-' and !ascii.isUpper(char)) {
                char = try it.advance() orelse return it.identifier[start..];
            }

            if (ascii.isUpper(char)) {
                it.rewind();
            }

            const end = it.offset - switch (char) {
                '-', '_' => @as(usize, 1),
                else => @as(usize, 0),
            };

            return it.identifier[start..end];
        }

        if (ascii.isUpper(char)) {
            char = try it.advance() orelse return it.identifier[start..];
            const upper_mode = ascii.isUpper(char);

            while (char != '_' and char != '-') {
                if (upper_mode and ascii.isLower(char)) {
                    it.rewind();
                    it.rewind();
                    break;
                }

                if (!upper_mode and ascii.isUpper(char)) {
                    it.rewind();
                    break;
                }

                char = try it.advance() orelse return it.identifier[start..];
            }

            const end = it.offset - switch (char) {
                '-', '_' => @as(usize, 1),
                else => @as(usize, 0),
            };

            return it.identifier[start..end];
        }

        return Error.InvalidIdentifier;
    }

    fn peek(it: SegmentIterator) ?u8 {
        return if (it.offset < it.identifier.len)
            it.identifier[it.offset]
        else
            null;
    }

    fn advance(it: *SegmentIterator) Error!?u8 {
        if (it.peek()) |char| {
            it.offset += 1;

            if (char != '_' and char != '-' and !ascii.isAlphanumeric(char)) {
                return Error.InvalidIdentifier;
            }

            return char;
        }

        return null;
    }

    fn rewind(it: *SegmentIterator) void {
        if (it.offset > 0) {
            it.offset -= 1;
        }
    }
};

test SegmentIterator {
    {
        var it: SegmentIterator = try .init("foo1_bar");
        try std.testing.expectEqualStrings("foo1", (try it.next()).?);
        try std.testing.expectEqualStrings("bar", (try it.next()).?);
        try std.testing.expectEqual(null, (try it.next()));
    }

    {
        var it: SegmentIterator = try .init("Foo1Bar");
        try std.testing.expectEqualStrings("Foo1", (try it.next()).?);
        try std.testing.expectEqualStrings("Bar", (try it.next()).?);
        try std.testing.expectEqual(null, (try it.next()));
    }

    {
        var it: SegmentIterator = try .init("foo1Bar");
        try std.testing.expectEqualStrings("foo1", (try it.next()).?);
        try std.testing.expectEqualStrings("Bar", (try it.next()).?);
        try std.testing.expectEqual(null, (try it.next()));
    }

    {
        var it: SegmentIterator = try .init("FOO1_BAR");
        try std.testing.expectEqualStrings("FOO1", (try it.next()).?);
        try std.testing.expectEqualStrings("BAR", (try it.next()).?);
        try std.testing.expectEqual(null, (try it.next()));
    }

    {
        var it: SegmentIterator = try .init("foo1-bar");
        try std.testing.expectEqualStrings("foo1", (try it.next()).?);
        try std.testing.expectEqualStrings("bar", (try it.next()).?);
        try std.testing.expectEqual(null, (try it.next()));
    }

    {
        var it: SegmentIterator = try .init("Foo1_Bar");
        try std.testing.expectEqualStrings("Foo1", (try it.next()).?);
        try std.testing.expectEqualStrings("Bar", (try it.next()).?);
        try std.testing.expectEqual(null, (try it.next()));
    }

    {
        var it: SegmentIterator = try .init("FOO1Bar");
        try std.testing.expectEqualStrings("FOO1", (try it.next()).?);
        try std.testing.expectEqualStrings("Bar", (try it.next()).?);
        try std.testing.expectEqual(null, (try it.next()));
    }
}
