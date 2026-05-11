const std = @import("std");
const math = std.math;
const Limb = math.big.Limb;
const raw = math.big.int.raw;
// const raw = @import("raw.zig");
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
            .llsignedor,
            .llsignedand,
            .llsignedxor,
            .llcmp,
            .llnormalize => @panic("TODO"),
            .lldiv1 => lldiv1,
            .lldiv0p5 => lldiv0p5,

            .llmulacc,
            .llmulaccLong,
            .llsquareBasecase,
            .llpow => @panic("TODO")
        };
    }
};

const Range = struct {
    ty: ScaleTy,
    min: usize,
    max: usize,
    base: usize,
    // TODO: variable step
    step: f64,
    current: f64,
    // Whether the range is minimized by the previous range
    depends: bool,

    // TODO: decades (like log paper)
    const ScaleTy = enum { none, one, linear, logarithmic };

    pub const none: Range = .{
        .ty = .none,
        .current = 1.0,
        .min = 0,
        .max = 0,
        .base = 0,
        .step = 0,
        .depends = false
    };

    pub fn one(comptime value: usize) Range {
        // assert(value > 0);
        return .{
            .ty = .one,
            .min = value,
            .current = @floatFromInt(value),
            .max = 0,
            .base = 0,
            .step = 1.0,
            .depends = false
        };
    }

    pub fn linear(min: usize, max: usize, nb_pts: usize) Range {
        assert(max > min);
        const step: f64 = @as(f64, @floatFromInt(max - min)) / (nb_pts - 1);
        // const minimum: f64 = if (min == 0) step else @floatFromInt(min);
        const minimum: f64 = @floatFromInt(min);
        // assert(minimum > 0.0);
        return .{
            .ty = .linear,
            .min = minimum,
            .max = max,
            .step = step,
            .current = minimum,
            .depends = false,//depends,
            .base = 0
        };
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
            .depends = false,//depends,
            .current = std.math.pow(f64, 10, @floatFromInt(min)),
        };
    }

    /// Duplicates the original range
    /// if `self.depends` is set, the new range's start value is larger
    /// than the `value` argument; otherwise, the argument is ignored
    pub fn init(self: @This(), value: usize) @This() {
        var new = self;
        new.current = @floatFromInt(new.min);
        if (self.depends) {
            while (new.peek()) |peeked| {
                if(peeked >= value) break;
                _ = new.next();
            }
        }
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
            .none => unreachable
        };
        return @intFromFloat(@round(next_value));
    }

    pub fn next(self: *@This()) ?usize {
        const res = self.peek();
        self.current += self.step;
        return res;
    }
};

const BenchFunction = fn (comptime op: raw.AccOp, r: []Limb, a: []const Limb, b: []const Limb, value: usize) void;

const Bench = struct {
    name: Functions,
    ops: bool = false,
    r: Range,

    /// Varies `a`
    /// Currently unused
    // a: Range,
    /// Varies `b`
    /// Currently unused
    // b: Range,
    /// Varies `value`
    value: Range = .none,

    /// Numbers of iteration
    // TODO: make it variable, i.e fn(r.len, a.len, b.len) usize
    iterations: usize = 100_000,
};


const bench_list: []const Bench = &.{
    Bench {
        .name = .lladdcarry,
        .r = .log(0, 4, 60),
    },
    Bench {
        .name = .llsubcarry,
        .r = .log(0, 4, 60),
    },
    Bench {
        .name = .llaccum,
        .r = .log(0, 4, 60),
        .ops = true
    },
    Bench {
        .name = .llmulLimb,
        .r = .log(0, 3, 50),
        .value = .linear(0, std.math.maxInt(Limb), 100),
        .ops = true,
        .iterations = 2000
    },
    // TODO: maybe more specific benches
    // Bench {
    //     .name = .llshl,
    //     .r = .log(0, 4, 100),
    //     .value = .linear(0, 500*64, 60)
    // },
    // Bench {
    //     .name = .llshr,
    //     .r = .log(0, 4, 100),
    //     .value = .linear(0, 500*64, 60),
    //     .iterations = 5000
    // },
    Bench {
        .name = .llnot,
        .r = .log(0, 4, 100),
        .iterations = 5000
    },
    Bench {
        .name = .lldiv1,
        .r = .log(0, 4, 100),
        .value = .linear(1, std.math.maxInt(Limb), 25),
        .iterations = 1000
    },
    Bench {
        .name = .lldiv0p5,
        .r = .log(0, 4, 100),
        .value = .linear(1, std.math.maxInt(math.big.HalfLimb), 25),
        .iterations = 1000
    },
};




const seed = 0;
const enable_warns = false;
var writer: ?*Io.Writer = null;
pub fn main(init: std.process.Init) !void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = handle_sigint },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);


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

        // const range_b_initial: Range = if(bench.b.isNone()) .one(1) else bench.b;
        // const range_a_initial: Range = if(bench.a.isNone()) .one(1) else bench.a;
        const range_r_initial: Range = if(bench.r.isNone()) .one(1) else bench.r;

        // var range_b = range_b_initial.init(0);
        // while (range_b.next()) |b_len| {

        //     var range_a = range_a_initial.init(b_len);
        //     while (range_a.next()) |a_len| {
        //         std.debug.print("Doing {}, a_len={}, b_len={}\n", .{bench.name, a_len, b_len});

        // var range_r = range_r_initial.init(a_len);
        var range_r = range_r_initial.init(0);
        while (range_r.next()) |r_len| {
            const a_len = r_len;
            const b_len = r_len;

            std.debug.print("Doing {}, n={}\n", .{bench.name, r_len});

            const ops = if(bench.ops) &.{ .add, .sub } else &.{ .add };
            inline for (ops) |op| {

                var range_value: Range = if (bench.value.isNone()) .one(0) else bench.value;
                while (range_value.next()) |value| {

                    const a = try randomLimbs(allocator, rand, a_len);
                    const b = try randomLimbs(allocator, rand, b_len);
                    const r = try randomLimbs(allocator, rand, r_len);
                    defer allocator.free(a);
                    defer allocator.free(b);
                    defer allocator.free(r);


                    // TODO: is it the best clock to use ?
                    const start = Io.Clock.now(.cpu_process, io);
                    for (0..bench.iterations) |_| {
                        @call(.never_inline, function, .{op, r, a, b, value});
                    }
                    const duration = start.untilNow(io, .cpu_process);
                    if (enable_warns and duration.toMilliseconds() == 0) 
                        // TODO: also add `value`
                        std.log.warn(
                            "Benchmark likely too short (less than 1ms of bench): {}, r={}, a={}, b={}, op={}, N={}",
                            .{bench.name, r_len, a_len, b_len, op, bench.iterations}
                        );
                    try logResult(logger, bench.name, r_len, a_len, b_len, op, value, @intCast(duration.toNanoseconds()), bench.iterations);
                }
                // std.debug.print("{}, r_len={} a_len={} b_len={}, d = {}, av = {}\n", .{bench.name, r_len, a_len, b_len, duration.toNanoseconds(), average});
            }
        }
        //    }
        //}
    }
}

// average in ns
fn logResult(logger: *Io.Writer, comptime name: Functions, r_len: usize, a_len: usize, b_len: usize, comptime op: raw.AccOp, value: usize, duration: u64, iterations: usize) Io.Writer.Error!void {
    const average: f64 = @as(f64, @floatFromInt(duration)) / @as(f64, @floatFromInt(iterations));
    try logger.print("\n{s},{s},{:.3},{},{},{},{s},{}", .{@tagName(name), @tagName(optMode), average, r_len, a_len, b_len, @tagName(op), value});
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
// Bench methods
// For 1 input array: varry its length
// For 2 input arrays: varry both length separately (usually, a.len >= b.len)

// at most linear:
// llaccum(comptime op: AccOp, r: []Limb, a: []const Limb) void
// lladdcarry(r: []Limb, a: []const Limb, b: []const Limb) Limb
// llsubcarry(r: []Limb, a: []const Limb, b: []const Limb) Limb
//
// llmulLimb(comptime op: AccOp, acc: []Limb, y: []const Limb, xi: Limb) bool
// llshl(r: []Limb, a: []const Limb, shift: usize) usize
// llshr(r: []Limb, a: []const Limb, shift: usize) usize
// llnot(r: []Limb) void
// llsignedor(r: []Limb, a: []const Limb, a_positive: bool, b: []const Limb, b_positive: bool) bool
// llsignedand(r: []Limb, a: []const Limb, a_positive: bool, b: []const Limb, b_positive: bool) bool
// llsignedxor(r: []Limb, a: []const Limb, a_positive: bool, b: []const Limb, b_positive: bool) bool
// lldiv1(quo: []Limb, rem: *Limb, a: []const Limb, b: Limb) void
// lldiv0p5(quo: []Limb, rem: *Limb, a: []const Limb, b: HalfLimb) void
//
// llcmp(a: []const Limb, b: []const Limb) i8
// llnormalize(a: []const Limb) usize
//
//
// at least quadratic:
// llmulacc(comptime op: AccOp, opt_allocator: ?Allocator, r: []Limb, a: []const Limb, b: []const Limb) void
// llmulaccLong(comptime op: AccOp, r: []Limb, a: []const Limb, b: []const Limb) void
// llsquareBasecase(r: []Limb, x: []const Limb) void
// llpow(r: []Limb, a: []const Limb, b: u32, tmp_limbs: []Limb) void
