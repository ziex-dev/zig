const std = @import("std");

var disable_mirror_b: std.atomic.Value(bool) = .init(false);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const zig_binary = args[1];
    const self_path = args[2];

    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 5674);
    var server = try address.listen(io, .{});
    defer server.deinit(io);

    var responder = try io.concurrent(respondThread, .{ io, &server });
    defer {
        if (@import("builtin").os.tag == .windows) {
            // https://codeberg.org/ziglang/zig/issues/30865
            var connection = address.connect(io, .{ .mode = .stream }) catch @panic("30865");
            connection.shutdown(io, .send) catch @panic("30865");
        }
        responder.cancel(io) catch {};
    }

    // test that it succeeds to download when the first mirror is wrong
    {
        try std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(arena, &.{ self_path, "dep_root", ".zig-cache" }));
        try std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(arena, &.{ self_path, "dep_root", "zig-pkg" }));
        try std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(arena, &.{ self_path, "dep_root", "zig-out" }));

        const zig_binary_shifted = if (std.fs.path.isAbsolute(zig_binary)) zig_binary else try std.fs.path.join(arena, &.{ "..", zig_binary });
        var build_proc = try std.process.spawn(io, .{
            .argv = &.{ zig_binary_shifted, "build", "--global-cache-dir", ".zig-cache", "--fetch=all" },
            .cwd = .{ .path = try std.fs.path.join(arena, &.{ self_path, "dep_root" }) },
        });
        const term = try build_proc.wait(io);
        if (term != .exited or term.exited != 0) return error.NonZeroExitCode;
    }

    disable_mirror_b.store(true, .seq_cst);

    // test that it fails to download when all mirrors are wrong
    {
        try std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(arena, &.{ self_path, "dep_root", ".zig-cache" }));
        try std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(arena, &.{ self_path, "dep_root", "zig-pkg" }));
        try std.Io.Dir.cwd().deleteTree(io, try std.fs.path.join(arena, &.{ self_path, "dep_root", "zig-out" }));

        const zig_binary_shifted = if (std.fs.path.isAbsolute(zig_binary)) zig_binary else try std.fs.path.join(arena, &.{ "..", zig_binary });
        var build_proc = try std.process.spawn(io, .{
            .argv = &.{ zig_binary_shifted, "build", "--global-cache-dir", ".zig-cache", "--fetch=all" },
            .cwd = .{ .path = try std.fs.path.join(arena, &.{ self_path, "dep_root" }) },
            .stderr = .pipe,
        });
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_reader = build_proc.stderr.?.reader(io, &stderr_buffer);
        const stderr_text = try stderr_reader.interface.allocRemaining(init.gpa, .unlimited);
        defer init.gpa.free(stderr_text);
        const term = try build_proc.wait(io);
        if (term != .exited or term.exited == 0) return error.ShouldHaveZeroExitCode;
    }
}

pub fn respondThread(io: std.Io, server: *std.Io.net.Server) !void {
    while (true) {
        const conn = try server.accept(io);
        try handleConnection(io, conn);
    }
}

pub fn handleConnection(io: std.Io, conn: std.Io.net.Stream) !void {
    defer conn.close(io);
    var recv_buffer: [4196]u8 = undefined;
    var send_buffer: [1024]u8 = undefined;
    var receiver = conn.reader(io, &recv_buffer);
    var sender = conn.writer(io, &send_buffer);

    var http_server = std.http.Server.init(&receiver.interface, &sender.interface);
    var req = try http_server.receiveHead();

    const files = dependencies.get(req.head.target) orelse {
        return req.respond("404", .{ .status = .not_found });
    };
    if (disable_mirror_b.load(.seq_cst) and std.mem.eql(u8, req.head.target, "/dep_b.tar")) {
        return req.respond("401", .{ .status = .unauthorized });
    }

    var respond_buffer: [4196]u8 = undefined;

    var response = try req.respondStreaming(&respond_buffer, .{
        .respond_options = .{
            .extra_headers = &.{.{
                .name = "Content-Type",
                .value = "application/x-tar",
            }},
        },
    });

    var tar: std.tar.Writer = .{ .underlying_writer = &response.writer };

    for (files) |file| {
        try tar.writeFileBytes(file.name, file.text, .{});
    }
    try tar.finishPedantically();

    try response.end();
}

const dependencies: std.StaticStringMap([]const File) = .initComptime(.{
    .{
        "/dep_a.tar", &[_]File{
            .{ .name = "build.zig", .text =
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {
            \\    _ = b; // stub
            \\}
            \\
            },
            .{ .name = "build.zig.zon", .text =
            \\.{
            \\    .name = .dep_a,
            \\    .version = "0.0.1",
            \\    .minimum_zig_version = "0.16.0-dev.2687+41594c190",
            \\    .paths = .{ "build.zig.zon", "build.zig" },
            \\    .dependencies = .{
            \\        .dep_b = .{
            \\            .url = "invalid url",
            \\            .hash = "dep_b-0.0.1-vr1FDxUBAAAzfEydzlYbY3bJSo8Ty3AWC6tKRfXycyuM",
            \\        },
            \\    },
            \\    .fingerprint = 0xf50f59a4bec497a7,
            \\}
            \\
            },
        },
    },
    .{
        "/dep_b.tar", &[_]File{
            .{ .name = "build.zig", .text =
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {
            \\    _ = b; // stub
            \\}
            \\
            },
            .{ .name = "build.zig.zon", .text =
            \\.{
            \\    .name = .dep_b,
            \\    .version = "0.0.1",
            \\    .minimum_zig_version = "0.16.0-dev.2687+41594c190",
            \\    .paths = .{ "build.zig.zon", "build.zig" },
            \\    .fingerprint = 0x6c06081e0f45bdbe,
            \\}
            \\
            },
        },
    },
});

const File = struct {
    name: []const u8,
    text: []const u8,
};
