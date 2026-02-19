//! Parses `~/.netrc` (or possibly `~/_netrc` on windows)
//! storing hosts and users declared within.
//! Ignores macros (macdef)

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

/// Contains the parsed info.
hosts: std.StringHashMapUnmanaged(User),
/// Used internall by the parser.
state: State,

pub const empty: NetrcParser = .{
    .hosts = .empty,
    .state = .{
        .fsm_state = .looking_for_host,
        .user = null,
    },
};

pub const User = struct {
    login: []const u8,
    password: []const u8,

    const empty: User = .{
        .login = "",
        .password = "",
    };
};

const DataKind = enum {
    login,
    password,
};

const State = struct {
    fsm_state: FsmState,
    user: ?*User,

    const FsmState = enum {
        looking_for_host,
        looking_for_login_or_password,
        looking_for_login,
        looking_for_password,
        skipping_login_and_password,
    };
};

const NetrcParseError = error{Malformed} || Allocator.Error;

const NetrcParser = @This();

pub fn deinit(parser: *NetrcParser, gpa: Allocator) void {
    var it = parser.hosts.iterator();
    while (it.next()) |entry| {
        gpa.free(entry.key_ptr.*);
        gpa.free(entry.value_ptr.login);
        gpa.free(entry.value_ptr.password);
    }

    parser.hosts.deinit(gpa);
}

/// Populates `hosts` with information contained in the provided file, if any.
pub fn parse(
    parser: *NetrcParser,
    gpa: Allocator,
    in: *std.Io.Reader,
) NetrcParseError!void {
    sw: switch (parser.state.fsm_state) {
        .looking_for_host => {
            assert(parser.state.user == null);

            const host = try nextHost(in);
            if (host.len == 0) {
                // EOF, not an error
                return;
            }

            try parser.hosts.ensureUnusedCapacity(gpa, 1);
            const kv = parser.hosts.getOrPutAssumeCapacity(host);
            if (kv.found_existing) {
                continue :sw .skipping_login_and_password;
            }

            kv.key_ptr.* = try gpa.dupe(u8, host);
            kv.value_ptr.* = .empty;
            parser.state.user = kv.value_ptr;

            continue :sw .looking_for_login_or_password;
        },
        .looking_for_login_or_password => {
            assert(parser.state.user != null);

            const user = parser.state.user.?;
            assert(user.login.len == 0);
            assert(user.password.len == 0);

            const data, const kind = try nextLoginOrPwd(in);
            assert(data.len != 0);

            switch (kind) {
                .login => user.login = try gpa.dupe(u8, data),
                .password => user.password = try gpa.dupe(u8, data),
            }

            if (user.login.len != 0 and user.password.len != 0) {
                parser.state.user = null;
                continue :sw .looking_for_host;
            }

            if (user.login.len == 0) {
                continue :sw .looking_for_login;
            }

            assert(user.password.len == 0);
            continue :sw .looking_for_password;
        },
        .looking_for_login => {
            assert(parser.state.user != null);

            const user = parser.state.user.?;
            assert(user.login.len == 0);
            assert(user.password.len != 0);

            const login = try nextLogin(in);
            assert(login.len != 0);

            user.login = try gpa.dupe(u8, login);
            parser.state.user = null;
            continue :sw .looking_for_host;
        },
        .looking_for_password => {
            assert(parser.state.user != null);

            const user = parser.state.user.?;
            assert(user.login.len != 0);
            assert(user.password.len == 0);

            const password = try nextPassword(in);
            assert(password.len != 0);

            user.password = try gpa.dupe(u8, password);
            parser.state.user = null;
            continue :sw .looking_for_host;
        },
        .skipping_login_and_password => {
            assert(parser.state.user == null);

            _ = nextToken(in); // login
            _ = nextToken(in); // login value
            _ = nextToken(in); // password
            _ = nextToken(in); // password value

            continue :sw .looking_for_host;
        },
    }
}

fn nextHost(in: *std.Io.Reader) NetrcParseError![]const u8 {
    var token = nextToken(in);
    if (std.mem.eql(u8, token, "macdef")) {
        try ignoreMacro(in);
        token = nextToken(in);
    }

    if (token.len == 0) {
        // EOF, not an error
        return "";
    }

    if (!std.mem.eql(u8, token, "machine")) {
        return error.Malformed;
    }

    return nextToken(in);
}

fn nextLoginOrPwd(
    in: *std.Io.Reader,
) NetrcParseError!struct { []const u8, DataKind } {
    const token = nextToken(in);
    if (token.len == 0) {
        return error.Malformed;
    }

    if (std.mem.eql(u8, token, "login")) {
        return .{ nextToken(in), .login };
    }

    if (std.mem.eql(u8, token, "password")) {
        return .{ nextToken(in), .password };
    }

    return error.Malformed;
}

fn nextLogin(in: *std.Io.Reader) NetrcParseError![]const u8 {
    const token = nextToken(in);
    if (std.mem.eql(u8, token, "login")) {
        return nextToken(in);
    }

    return error.Malformed;
}

fn nextPassword(in: *std.Io.Reader) NetrcParseError![]const u8 {
    const token = nextToken(in);
    if (std.mem.eql(u8, token, "password")) {
        return nextToken(in);
    }

    return error.Malformed;
}

fn nextToken(in: *std.Io.Reader) []const u8 {
    // toss away whitespace before tokens
    while (true) {
        const b = in.peekByte() catch return "";
        if (b != ' ' and b != '\t' and b != '\n' and b != '\r') {
            break;
        }

        in.toss(1);
    }

    // count the characters in the token
    const token_size = blk: {
        const seek = in.seek;
        defer in.seek = seek;

        var size: usize = 0;
        while (true) {
            const b = in.peekByte() catch break :blk size;
            if (b == ' ' or b == '\t' or b == '\n' or b == '\r') {
                break :blk size;
            }

            size += 1;
            in.seek += 1;
        }
    };

    return in.take(token_size) catch unreachable;
}

fn ignoreMacro(in: *std.Io.Reader) NetrcParseError!void {
    while (true) {
        _ = in.discardDelimiterInclusive('\n') catch return;

        const b = in.peekByte() catch return;
        if (b == '\n') {
            in.toss(1);
            return;
        }
    }
}

test "can parse single line machine" {
    const gpa = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("machine foo.com login user password secret42");

    var p: NetrcParser = .empty;
    defer p.deinit(gpa);

    try p.parse(gpa, &reader);
    try std.testing.expect(p.hosts.contains("foo.com"));
    try std.testing.expectEqualSlices(u8, "user", p.hosts.get("foo.com").?.login);
    try std.testing.expectEqualSlices(u8, "secret42", p.hosts.get("foo.com").?.password);
}

test "can parse multi line machine" {
    const gpa = std.testing.allocator;
    var reader: std.Io.Reader = .fixed(
        \\machine foo.com
        \\login user
        \\password secret42
    );

    var p: NetrcParser = .empty;
    defer p.deinit(gpa);

    try p.parse(gpa, &reader);
    try std.testing.expect(p.hosts.contains("foo.com"));
    try std.testing.expectEqualSlices(u8, "user", p.hosts.get("foo.com").?.login);
    try std.testing.expectEqualSlices(u8, "secret42", p.hosts.get("foo.com").?.password);
}

test "is whitespace resilient" {
    const gpa = std.testing.allocator;
    var reader: std.Io.Reader = .fixed( //
        "\t  \n" //
        ++ "machine\t\tfoo.com\t login\n" //
        ++ "\t  \n" //
        ++ "\n" //
        ++ "\t\tuser\r\n" //
        ++ "                                    password\n" //
        ++ " \n" //
        ++ "  \n" //
        ++ "   \n" //
        ++ "    \n" //
        ++ "\t  \t\t  \n" //
        ++ "\n" //
        ++ " secret42\n",
    );

    var p: NetrcParser = .empty;
    defer p.deinit(gpa);

    try p.parse(gpa, &reader);
    try std.testing.expect(p.hosts.contains("foo.com"));
    try std.testing.expectEqualSlices(u8, "user", p.hosts.get("foo.com").?.login);
    try std.testing.expectEqualSlices(u8, "secret42", p.hosts.get("foo.com").?.password);
}

test "can parse multiple hosts" {
    const gpa = std.testing.allocator;
    var reader: std.Io.Reader = .fixed(
        \\machine foo.com login user password secret42
        \\machine bar.com login user password secret42
    );

    var p: NetrcParser = .empty;
    defer p.deinit(gpa);

    try p.parse(gpa, &reader);
    try std.testing.expect(p.hosts.contains("foo.com"));
    try std.testing.expect(p.hosts.contains("bar.com"));
    try std.testing.expectEqualSlices(u8, "user", p.hosts.get("foo.com").?.login);
    try std.testing.expectEqualSlices(u8, "user", p.hosts.get("bar.com").?.login);
    try std.testing.expectEqualSlices(u8, "secret42", p.hosts.get("foo.com").?.password);
    try std.testing.expectEqualSlices(u8, "secret42", p.hosts.get("bar.com").?.password);
}

test "ignores later logins for same machine" {
    const gpa = std.testing.allocator;
    var reader: std.Io.Reader = .fixed(
        \\machine foo.com login user1 password secret42
        \\machine foo.com login user2 password secret43
        \\machine bar.com login user3 password secret44
    );

    var p: NetrcParser = .empty;
    defer p.deinit(gpa);

    try p.parse(gpa, &reader);
    try std.testing.expect(p.hosts.contains("foo.com"));
    try std.testing.expect(p.hosts.contains("bar.com"));
    try std.testing.expectEqualSlices(u8, "user1", p.hosts.get("foo.com").?.login);
    try std.testing.expectEqualSlices(u8, "secret42", p.hosts.get("foo.com").?.password);
    try std.testing.expectEqualSlices(u8, "user3", p.hosts.get("bar.com").?.login);
    try std.testing.expectEqualSlices(u8, "secret44", p.hosts.get("bar.com").?.password);
}

test "ignores macros" {
    const gpa = std.testing.allocator;
    var reader: std.Io.Reader = .fixed(
        \\macdef start_macro
        \\macros should be ignored at the beginning
        \\macros are delimited by consecutive newlines
        \\they can be arbitrarily long
        \\
        \\
        \\machine foo.com login user password secret42
        \\macdef ending_macro
        \\macros at the end must also be properly ignored
    );

    var p: NetrcParser = .empty;
    defer p.deinit(gpa);

    try p.parse(gpa, &reader);
    try std.testing.expect(p.hosts.contains("foo.com"));
    try std.testing.expectEqualSlices(u8, "user", p.hosts.get("foo.com").?.login);
    try std.testing.expectEqualSlices(u8, "secret42", p.hosts.get("foo.com").?.password);
}
