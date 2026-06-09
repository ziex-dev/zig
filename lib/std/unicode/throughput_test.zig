const std = @import("std");
const Io = std.Io;
const time = std.time;
const unicode = std.unicode;

fn utf16LeValidateSlice(input: []const u8) void {
    _ = std.mem.doNotOptimizeAway(unicode.utf16ValidateSlice(input, .little));
}

fn utf8CountCodepoints(input: []const u8) void {
    _ = std.mem.doNotOptimizeAway(unicode.utf8CountCodepoints(input) catch {});
}

const N = 1_000_000;

const KiB = 1024;
const MiB = 1024 * KiB;
const GiB = 1024 * MiB;

fn benchTime(io: Io) i96 {
    return Io.Clock.awake.now(io).nanoseconds;
}

fn benchmark(comptime function: fn ([]const u8) void, buf: []const u8, io: Io) u64 {
    const bytes = N * buf.len;

    const start = benchTime(io);
    var i: usize = 0;
    while (i < N) : (i += 1) {
        @call(
            .never_inline,
            function,
            .{buf},
        );
    }
    const end = benchTime(io);

    const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
    const throughput = @as(u64, @intFromFloat(@as(f64, @floatFromInt(bytes)) / elapsed_s));

    return throughput;
}

pub fn main(init: std.process.Init) !void {
    // Size of buffer is about size of printed message.
    const io = init.io;
    var stdout_buffer: [0x100]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("utf8CountCodepoints: short ASCII strings\n", .{});
    try stdout.flush();
    {
        const throughput = benchmark(utf8CountCodepoints, "abc", io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }
    try stdout.print("utf8CountCodepoints: short Unicode strings\n", .{});
    try stdout.flush();
    {
        const throughput = benchmark(utf8CountCodepoints, "ŌŌŌ", io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }

    try stdout.print("utf8CountCodepoints: pure ASCII strings\n", .{});
    try stdout.flush();
    {
        const part = "hello";
        const buf: [128][part.len]u8 = @splat(part.*);
        const throughput = benchmark(utf8CountCodepoints, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }

    try stdout.print("utf8CountCodepoints: pure Unicode strings\n", .{});
    try stdout.flush();
    {
        const part = "こんにちは";
        const buf: [16][part.len]u8 = @splat(part.*);
        const throughput = benchmark(utf8CountCodepoints, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }

    try stdout.print("utf8CountCodepoints: mixed ASCII/Unicode strings\n", .{});
    try stdout.flush();
    {
        const part = "Hyvää huomenta";
        const buf: [16][part.len]u8 = @splat(part.*);
        const throughput = benchmark(utf8CountCodepoints, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }
    try stdout.flush();

    try stdout.print("utf16ValidateSlice: mixed ASCII/Unicode strings\n", .{});
    try stdout.flush();
    {
        const part = "\x61\x00\x62\x00\x63\x00\x3c\xd8\x0e\xdf";
        const buf: [16][part.len]u8 = @splat(part.*);
        const throughput = benchmark(utf16LeValidateSlice, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }
    try stdout.flush();
}
