const std = @import("std");
const Io = std.Io;
const time = std.time;
const unicode = std.unicode;

fn utf16LeValidateSlice(input: []const u16) void {
    _ = std.mem.doNotOptimizeAway(unicode.utf16ValidateSlice(input, .little));
}

fn utf16LeCountCodepoints(input: []const u16) void {
    const s = unicode.Utf16View.initUnchecked(input, .little);
    _ = std.mem.doNotOptimizeAway(s.countCodepoints());
}

fn utf8CountCodepoints(input: []const u8) void {
    const s = unicode.Utf8View.initUnchecked(input);
    _ = std.mem.doNotOptimizeAway(s.countCodepoints());
}

const N = 1_000_000;

const KiB = 1024;
const MiB = 1024 * KiB;
const GiB = 1024 * MiB;

fn benchTime(io: Io) i96 {
    return Io.Clock.awake.now(io).nanoseconds;
}

fn benchmark(
    comptime T: type,
    comptime function: fn ([]const T) void,
    buf: []const T,
    io: Io,
) u64 {
    const bytes = N * (buf.len * @sizeOf(T));

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

    try stdout.print("Utf8View.countCodepoints: short ASCII strings\n", .{});
    try stdout.flush();
    {
        const throughput = benchmark(u8, utf8CountCodepoints, "abc", io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }
    try stdout.print("Utf8View.countCodepoints: short Unicode strings\n", .{});
    try stdout.flush();
    {
        const throughput = benchmark(u8, utf8CountCodepoints, "ŌŌŌ", io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }

    try stdout.print("Utf8View.countCodepoints: pure ASCII strings\n", .{});
    try stdout.flush();
    {
        const part = "hello";
        const buf: [128][part.len]u8 = @splat(part.*);
        const throughput = benchmark(u8, utf8CountCodepoints, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }

    try stdout.print("Utf8View.countCodepoints: pure Unicode strings\n", .{});
    try stdout.flush();
    {
        const part = "こんにちは";
        const buf: [16][part.len]u8 = @splat(part.*);
        const throughput = benchmark(u8, utf8CountCodepoints, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }

    try stdout.print("Utf8View.countCodepoints: mixed ASCII/Unicode strings\n", .{});
    try stdout.flush();
    {
        const part = "Hyvää huomenta";
        const buf: [16][part.len]u8 = @splat(part.*);
        const throughput = benchmark(u8, utf8CountCodepoints, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }
    try stdout.flush();

    try stdout.print("utf16ValidateSlice: mixed ASCII/Unicode strings\n", .{});
    try stdout.flush();
    {
        const part = unicode.utf8ToUtf16StringLiteral("abc🌎", .little);
        const buf: [16][part.len]u16 = @splat(part.*);
        const throughput = benchmark(u16, utf16LeValidateSlice, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }
    try stdout.flush();

    try stdout.print("Utf16View.countCodepoints: mixed ASCII/Unicode strings\n", .{});
    try stdout.flush();
    {
        const part = unicode.utf8ToUtf16StringLiteral("abc🌎", .little);
        const buf: [16][part.len]u16 = @splat(part.*);
        const throughput = benchmark(u16, utf16LeCountCodepoints, @ptrCast(&buf), io);
        try stdout.print("  count: {:5} MiB/s\n", .{throughput / (1 * MiB)});
    }
    try stdout.flush();
}
