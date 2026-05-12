// zig run -O ReleaseFast --zig-lib-dir lib lib/std/math/big/benchmark.zig -- -f 0.5
// the argument "-f" is a multiplier for the number of iterations
// allows to decrease / increase the number of iterations depending on the machine

const std = @import("std");
const math = std.math;
const Limb = math.big.Limb;
const raw = math.big.int.raw;
const Random = std.Random.DefaultPrng;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;
const optMode = @import("builtin").mode;

comptime {
    // We need this, since some functions take a `Limb` as argument (i.e. llmulLimb)
    // and other take a `usize` (i.e. llshl, llshr)
    assert(Limb == usize);
}

const Functions = enum {
    // at most linear
    llaccum,
    lladdcarry,
    llsubcarry,
    llmulLimb,
    llshl,
    llshr,
    llnot,
    llsignedor,
    llsignedand,
    llsignedxor,
    llcmp,
    llnormalize,
    lldiv1,
    lldiv0p5,

    // mostly non linear
    llmulacc,
    llmulaccLong,
    llsquareBasecase,
    llpow,

    pub fn func(comptime self: Functions) BenchFunction {
        return switch (self) {
            .llaccum => llaccum,
            .lladdcarry => lladdcarry,
            .llsubcarry => llsubcarry,
            .llmulLimb => llmulLimb,
            .llshl => llshl,
            .llshr => llshr,
            .llnot => llnot,
            .llsignedor => llsignedor,
            .llsignedand => llsignedand,
            .llsignedxor => llsignedxor,
            .llcmp => llcmp,
            .llnormalize => llnormalize,
            .lldiv1 => lldiv1,
            .lldiv0p5 => lldiv0p5,

            .llmulacc => @compileError("TODO"),
            .llmulaccLong => llmulaccLong,
            .llsquareBasecase => llsquareBasecase,
            .llpow => @compileError("TODO"),
        };
    }

    pub fn isLinear(self: Functions) bool {
        return switch (self) {
            .llaccum,
            .lladdcarry,
            .llsubcarry,
            .llmulLimb,
            .llshl,
            .llshr,
            .llnot,
            .llsignedor,
            .llsignedand,
            .llsignedxor,
            // these 2 are technically at most linear
            .llcmp,
            .llnormalize,
            .lldiv1,
            .lldiv0p5,
            => true,

            .llmulacc, .llmulaccLong, .llsquareBasecase, .llpow => false,
        };
    }
};

const Range = struct {
    ty: ScaleTy,
    min: usize,
    max: usize,
    base: usize,
    step: f64,
    current: f64,

    // TODO: decades (like log paper) ?
    const ScaleTy = enum { none, one, linear, logarithmic };

    pub const none: Range = .{
        .ty = .none,
        .current = 1.0,
        .min = 0,
        .max = 0,
        .base = 0,
        .step = 0,
    };

    pub fn one(comptime value: usize) Range {
        return .{
            .ty = .one,
            .min = value,
            .current = @floatFromInt(value),
            .max = value,
            .base = 0,
            .step = 1.0,
        };
    }

    pub fn linear(min: usize, max: usize, nb_pts: usize) Range {
        assert(max > min);

        const step: f64 = @as(f64, @floatFromInt(max - min)) / (nb_pts - 1);
        const minimum: f64 = @floatFromInt(min);

        return .{ .ty = .linear, .min = minimum, .max = max, .step = step, .current = minimum, .base = 0 };
    }

    // Log scale between `10^min` and `10^max`
    pub fn log(min: usize, max: usize, nb_pts: usize) Range {
        assert(max > min);
        assert(nb_pts > 2);
        return .{
            .ty = .logarithmic,
            .min = min,
            .max = max,
            .base = 10,
            .step = @as(f64, @floatFromInt(max - min)) / (nb_pts - 1),
            .current = @floatFromInt(min),
        };
    }

    /// Duplicates the original range
    pub fn reinit(self: @This()) @This() {
        var new = self;
        new.current = @floatFromInt(new.min);
        return new;
    }

    pub fn isNone(self: @This()) bool {
        return self.ty == .none;
    }

    pub fn peek(self: *@This()) ?usize {
        const current = self.current;
        const max: f64 = @floatFromInt(self.max);

        const epsilon = 0.0001;
        if (current >= max + epsilon) return null;

        const next_value = switch (self.ty) {
            .one, .linear => current,
            .logarithmic => std.math.pow(f64, @floatFromInt(self.base), current),
            .none => unreachable,
        };
        return @intFromFloat(@round(next_value));
    }

    pub fn next(self: *@This()) ?usize {
        const res = self.peek();
        self.current += self.step;
        return res;
    }

    pub fn count(self: @This()) usize {
        var new = self.reinit();
        var n: usize = 0;
        while (new.next()) |_|
            n += 1;
        return n;
    }
};

const BenchFunction = fn (comptime op: raw.AccOp, r: []Limb, a: []const Limb, b: []const Limb, value: usize) void;

const Bench = struct {
    name: Functions,
    ops: bool = false,

    /// Number of limbs in `r`, `a` and `b`
    n: Range,
    value: Range = .none,

    /// Numbers of iteration
    // TODO: make it variable, i.e fn(r.len, a.len, b.len) usize
    iterations: usize = 100_000,
};

// TODO:
// specific benches for llshl, llshr, llnormalize and llcmp
const bench_list: []const Bench = &.{
    Bench{
        .name = .lladdcarry,
        .n = .log(0, 4, 60),
    },
    Bench{
        .name = .llsubcarry,
        .n = .log(0, 4, 60),
    },
    Bench{ .name = .llaccum, .n = .log(0, 4, 60), .ops = true },
    Bench{
        .name = .llmulLimb,
        .n = .log(0, 3, 60),
        // the speed should not depend on the value
        // also, we can't use too large of a number here,
        // otherwise, the range break due to floats handling of large values
        .value = .one(532762),
        .ops = true,
        .iterations = 100_000,
    },
    Bench{
        .name = .llnot,
        .n = .log(0, 4, 100),
    },
    Bench{
        .name = .lldiv1,
        .n = .log(0, 4, 100),
        // same as llmulLimb
        .value = .one(std.math.maxInt(math.big.HalfLimb)),
        .iterations = 10_000,
    },
    Bench{
        .name = .lldiv0p5,
        .n = .log(0, 4, 100),
        // same as lldiv1
        .value = .one(std.math.maxInt(math.big.HalfLimb) / 52),
        .iterations = 10_000,
    },
    Bench{ .name = .llsignedor, .n = .log(0, 4, 100), .iterations = 20_000, .value = .linear(0b00, 0b11, 4) },
    Bench{ .name = .llsignedand, .n = .log(0, 4, 100), .iterations = 20_000, .value = .linear(0b00, 0b11, 4) },
    Bench{ .name = .llsignedxor, .n = .log(0, 4, 100), .iterations = 20_000, .value = .linear(0b00, 0b11, 4) },
    Bench{ .name = .llmulaccLong, .n = .log(0, 3, 100), .iterations = 500, .ops = true },
    Bench{ .name = .llsquareBasecase, .n = .log(0, 3, 100), .iterations = 500 },
};

const seed = 0;
const enable_warns = false;
var iteration_factor: f64 = 1.0;
var writer: ?*Io.Writer = null;

pub fn main(init: std.process.Init) !void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = handle_sigint },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);

    var arg_it = init.minimal.args.iterate();
    while (arg_it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--iteration-factor")) {
            const next = arg["--iteration-factor".len..];
            if (next.len > 0) {
                if (next[0] != '=') std.debug.panic("Invalid argument: \"{s}\"\n", .{arg});
                if (next.len == 1) std.debug.panic("Expected a value after '=' for argument \"{s}\"\n", .{arg});
                const factor = std.fmt.parseFloat(f64, next[1..]) catch std.debug.panic("Invalid float for iteration factor: \"{s}\"\n", .{next[1..]});

                iteration_factor = factor;
            } else {
                const next_arg = arg_it.next() orelse std.debug.panic("Expected a value after \"--iteration-factor\"\n", .{});
                const factor = std.fmt.parseFloat(f64, next_arg) catch std.debug.panic("Invalid float for iteration factor: \"{s}\"\n", .{next_arg});

                iteration_factor = factor;
            }
        } else if (std.mem.startsWith(u8, arg, "-f")) {
            if (arg.len > 2) std.debug.panic("Argument iteration factor \"{s}\" too long\n", .{arg});

            const next_arg = arg_it.next() orelse std.debug.panic("Expected a value after \"-f\"\n", .{});
            const factor = std.fmt.parseFloat(f64, next_arg) catch std.debug.panic("Invalid float for iteration factor: \"{s}\"\n", .{next_arg});

            iteration_factor = factor;
        }
    }

    const io = init.io;
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    var rand: Random = .init(seed);

    var buffer: [1024 * 1024]u8 = undefined;
    var output_file = try Io.Dir.cwd().createFile(io, "stats.csv", .{ .exclusive = false });
    defer output_file.close(io);

    var logger = output_file.writer(io, &buffer);
    try logger.interface.writeAll("name,debug mode,average duration (ns),r_len,a_len,b_len,operation,value");
    writer = &logger.interface;

    try benchSimple(io, &arena, &rand, &logger.interface, bench_list);

    try logger.flush();
    writer = null;
}

fn handle_sigint(_: std.posix.SIG) callconv(.c) void {
    if (writer) |w| w.flush() catch @panic("Could not flush writer");
    std.process.exit(0);
}

fn normalize(a: []const Limb) usize {
    assert(a.len > 0);
    var i = a.len;
    while (a[i - 1] == 0) i -= 1;

    return i;
}

fn randomLimbs(allocator: Allocator, rand: *Random, n: usize) Allocator.Error![]Limb {
    assert(n > 0);
    const bytes = try allocator.alignedAlloc(u8, .of(Limb), n * @sizeOf(Limb));
    const limbs = std.mem.bytesAsSlice(Limb, bytes);

    rand.fill(bytes);
    while (normalize(limbs) == 0) rand.fill(bytes);

    return limbs[0..normalize(limbs)];
}

fn benchSimple(io: Io, arena: *std.heap.ArenaAllocator, rand: *Random, logger: *Io.Writer, comptime benches: []const Bench) !void {
    defer assert(arena.reset(.retain_capacity));
    const allocator = arena.allocator();

    // TODO: preallocate

    inline for (benches) |bench| {
        const function = bench.name.func();
        const N: usize = @intFromFloat(@as(f64, @floatFromInt(bench.iterations)) * iteration_factor);

        const range_n_initial: Range = if (bench.n.isNone()) .one(1) else bench.n;

        const count = range_n_initial.count();

        const ops = if (bench.ops) &.{ .add, .sub } else &.{.add};
        inline for (ops) |op| {
            var range_value: Range = if (bench.value.isNone()) .one(0) else bench.value;
            while (range_value.next()) |value| {
                const n_limbs = try allocator.alloc(usize, count);
                const times = try allocator.alloc(f64, count);
                defer allocator.free(n_limbs);
                defer allocator.free(times);
                var i: usize = 0;

                const bench_start = Io.Clock.now(.cpu_process, io);

                var range_n = range_n_initial.reinit();
                while (range_n.next()) |n| : (i += 1) {
                    const a_len = n;
                    const b_len = n;

                    const additional_limbs = switch (bench.name) {
                        // these functions may require r.len >= a.len + 1
                        .llsignedor, .llsignedxor, .llsignedand => 1,
                        // not necessarily needed for llmulaccLong
                        .llmulaccLong => n,
                        .llsquareBasecase => n + 1,
                        else => 0,
                    };

                    const a = try randomLimbs(allocator, rand, a_len);
                    const b = try randomLimbs(allocator, rand, b_len);
                    const r = try randomLimbs(allocator, rand, n + additional_limbs);
                    defer allocator.free(a);
                    defer allocator.free(b);
                    defer allocator.free(r);

                    // TODO: is it the best clock to use ?
                    const start = Io.Clock.now(.cpu_process, io);
                    for (0..N) |_| {
                        @call(.never_inline, function, .{ op, r, a, b, value });
                    }
                    const duration = start.untilNow(io, .cpu_process);

                    if (enable_warns and duration.toMilliseconds() == 0) {
                        std.log.warn("Benchmark likely too short (less than 1ms of bench): {}, r={}, a={}, b={}, op={}, value={} N={}", .{ bench.name, n, a_len, b_len, op, value, N });
                    }

                    const average: f64 = @as(f64, @floatFromInt(duration.toNanoseconds())) / @as(f64, @floatFromInt(N));

                    try logResult(logger, bench.name, n, a_len, b_len, op, value, average);
                    n_limbs[i] = n;
                    times[i] = average;
                }
                const bench_duration = bench_start.untilNow(io, .cpu_process).toMilliseconds();

                logProgress(bench.name, op, n_limbs, times, value, @intCast(bench_duration), N);
            }
        }
    }
}

fn logProgress(comptime name: Functions, comptime op: raw.AccOp, n_limbs: []const usize, times: []const f64, value: usize, bench_duration: u64, N: usize) void {
    // in these format strings:
    // 16 is the max tag length of `name`
    // 20 is the max digits of a u64 in base 10
    // 5 is a guess at the max digits of the limb rate
    // 5 is a guess at the max digits of the duration time
    // 6 is a guess at the max digits of the iteration count
    if (name.isLinear()) {
        const regression = linearRegression(n_limbs, times);
        const ns_per_limb = regression[1];
        const limb_per_us: usize = @intFromFloat(std.time.ns_per_us / ns_per_limb);

        const fmt_str = "{s: <16}, op={}, value={: >20}, {: >5} limbs/µs (done in {: >5}ms, {: >6} iterations)\n";
        std.debug.print(fmt_str, .{ @tagName(name), op, value, limb_per_us, bench_duration, N });
    } else {
        std.debug.print("{s: <16}, op={}, value={: >20}, {s: >14} (done in {: >5}ms, {: >6} iterations)\n", .{ @tagName(name), op, value, "", bench_duration, N });
    }
}

// average in ns
fn logResult(logger: *Io.Writer, comptime name: Functions, r_len: usize, a_len: usize, b_len: usize, comptime op: raw.AccOp, value: usize, average: f64) Io.Writer.Error!void {
    try logger.print("\n{s},{s},{:.3},{},{},{},{s},{}", .{ @tagName(name), @tagName(optMode), average, r_len, a_len, b_len, @tagName(op), value });
}

// Fits the data to the line y = a + b.x, and returns .{a, b}
// https://en.wikipedia.org/wiki/Simple_linear_regression
fn linearRegression(X: []const usize, Y: []const f64) struct { f64, f64 } {
    assert(X.len == Y.len);
    const n: f64 = @floatFromInt(X.len);
    var x_sum: f64 = 0.0;
    var x_sqr_sum: f64 = 0.0;
    var y_sum: f64 = 0.0;
    var xy_sum: f64 = 0.0;
    for (X, Y) |x, y| {
        x_sum += @floatFromInt(x);
        y_sum += y;
        x_sqr_sum += @floatFromInt(x * x);
        xy_sum += y * @as(f64, @floatFromInt(x));
    }

    const denominator = (n * x_sqr_sum - x_sum * x_sum);
    const a = (y_sum * x_sqr_sum - x_sum * xy_sum) / denominator;
    const b = (n * xy_sum - x_sum * y_sum) / denominator;

    return .{ a, b };
}

fn lladdcarry(comptime _: raw.AccOp, r: []Limb, a: []const Limb, b: []const Limb, _: usize) void {
    const res = raw.lladdcarry(r, a, b);
    std.mem.doNotOptimizeAway(res);
}
fn llsubcarry(comptime _: raw.AccOp, r: []Limb, a: []const Limb, b: []const Limb, _: usize) void {
    const res = raw.llsubcarry(r, a, b);
    std.mem.doNotOptimizeAway(res);
}

fn llaccum(comptime op: raw.AccOp, r: []Limb, a: []const Limb, _: []const Limb, _: usize) void {
    raw.llaccum(op, r, a);
}

fn llmulLimb(comptime op: raw.AccOp, r: []Limb, a: []const Limb, _: []const Limb, value: usize) void {
    const res = raw.llmulLimb(op, r, a, value);
    std.mem.doNotOptimizeAway(res);
}

fn llshl(comptime _: raw.AccOp, r: []Limb, a: []const Limb, _: []const Limb, value: usize) void {
    const res = raw.llshl(r, a, value);
    std.mem.doNotOptimizeAway(res);
}

fn llshr(comptime _: raw.AccOp, r: []Limb, a: []const Limb, _: []const Limb, value: usize) void {
    const res = raw.llshr(r, a, value);
    std.mem.doNotOptimizeAway(res);
}

fn llnot(comptime _: raw.AccOp, r: []Limb, _: []const Limb, _: []const Limb, _: usize) void {
    raw.llnot(r);
}

fn lldiv1(comptime _: raw.AccOp, r: []Limb, a: []const Limb, _: []const Limb, value: usize) void {
    var rem: Limb = undefined;
    raw.lldiv1(r, &rem, a, value);
    std.mem.doNotOptimizeAway(rem);
}

fn lldiv0p5(comptime _: raw.AccOp, r: []Limb, a: []const Limb, _: []const Limb, value: usize) void {
    var rem: Limb = undefined;
    raw.lldiv0p5(r, &rem, a, std.math.cast(math.big.HalfLimb, value).?);
    std.mem.doNotOptimizeAway(rem);
}

fn llcmp(comptime _: raw.AccOp, _: []Limb, a: []const Limb, b: []const Limb, _: usize) void {
    const res = raw.llcmp(a, b);
    std.mem.doNotOptimizeAway(res);
}

fn llnormalize(comptime _: raw.AccOp, _: []Limb, a: []const Limb, _: []const Limb, _: usize) void {
    const res = raw.llnormalize(a);
    std.mem.doNotOptimizeAway(res);
}

fn llsignedor(comptime _: raw.AccOp, r: []Limb, a: []const Limb, b: []const Limb, value: usize) void {
    assert(value <= 0b11);
    const a_positive = value & 0b01 != 0;
    const b_positive = value & 0b10 != 0;
    const res = raw.llsignedor(r, a, a_positive, b, b_positive);
    std.mem.doNotOptimizeAway(res);
}

fn llsignedand(comptime _: raw.AccOp, r: []Limb, a: []const Limb, b: []const Limb, value: usize) void {
    assert(value <= 0b11);
    const a_positive = value & 0b01 != 0;
    const b_positive = value & 0b10 != 0;
    const res = raw.llsignedand(r, a, a_positive, b, b_positive);
    std.mem.doNotOptimizeAway(res);
}

fn llsignedxor(comptime _: raw.AccOp, r: []Limb, a: []const Limb, b: []const Limb, value: usize) void {
    assert(value <= 0b11);
    const a_positive = value & 0b01 != 0;
    const b_positive = value & 0b10 != 0;
    const res = raw.llsignedxor(r, a, a_positive, b, b_positive);
    std.mem.doNotOptimizeAway(res);
}

fn llmulaccLong(comptime op: raw.AccOp, r: []Limb, a: []const Limb, b: []const Limb, _: usize) void {
    raw.llmulaccLong(op, r, a, b);
}

fn llsquareBasecase(comptime _: raw.AccOp, r: []Limb, a: []const Limb, _: []const Limb, _: usize) void {
    raw.llsquareBasecase(r, a);
}
