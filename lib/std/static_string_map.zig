const std = @import("std.zig");
const mem = std.mem;

/// Static string map optimized for small sets of disparate string keys.
/// Works by separating the keys by length at initialization and only checking
/// strings of equal length at runtime.
pub fn StaticStringMap(comptime V: type) type {
    return StaticStringMapWithEql(V, defaultEql);
}

/// Like `std.mem.eql`, but takes advantage of the fact that the lengths
/// of `a` and `b` are known to be equal.
pub fn defaultEql(a: []const u8, b: []const u8) bool {
    if (a.ptr == b.ptr) return true;
    for (a, b) |a_elem, b_elem| {
        if (a_elem != b_elem) return false;
    }
    return true;
}

/// Like `std.ascii.eqlIgnoreCase` but takes advantage of the fact that
/// the lengths of `a` and `b` are known to be equal.
pub fn eqlAsciiIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.ptr == b.ptr) return true;
    for (a, b) |a_c, b_c| {
        if (std.ascii.toLower(a_c) != std.ascii.toLower(b_c)) return false;
    }
    return true;
}

/// StaticStringMap, but accepts an equality function (`eql`).
/// The `eql` function is only called to determine the equality
/// of equal length strings. Any strings that are not equal length
/// are never compared using the `eql` function.
pub fn StaticStringMapWithEql(
    comptime V: type,
    comptime eql: fn (a: []const u8, b: []const u8) bool,
) type {
    return struct {
        /// sorted ascending by length
        ks: [*]const []const u8,
        vs: [*]const V,
        chunks: [*]const u32,
        shortest: u32,
        longest: u32,

        pub const KV = struct { key: []const u8, value: V };

        /// Creates a map backed by static, `comptime`-allocated memory.
        ///
        /// `kvs_list` must be either a list of `struct { []const u8, V }`
        /// (key-value pairs), or a list of `struct { []const u8 }` (only
        /// keys) if `V` is `void`.
        pub inline fn initComptime(comptime kvs_list: anytype) Self {
            comptime {
                if (kvs_list.len == 0) return empty;
                if (kvs_list.len > std.math.maxInt(u32)) @compileError("too many entries");

                // because the keys are sorted, we grow proportionally to `n log(n)``
                @setEvalBranchQuota(10 * kvs_list.len * std.math.log2_int_ceil(usize, kvs_list.len));

                const shortest, const longest, const chunks_len = lengthBounds(kvs_list) orelse
                    @compileError("keys too long");
                var ks: [kvs_list.len][]const u8 = undefined;
                var vs: [kvs_list.len]V = undefined;
                var chunks: [chunks_len]u32 = undefined;
                populate(kvs_list, &ks, &vs, &chunks, shortest);

                const frozen_ks = ks;
                const frozen_vs = vs;
                const frozen_chunks = chunks;
                return .{
                    .ks = &frozen_ks,
                    .vs = &frozen_vs,
                    .chunks = &frozen_chunks,
                    .shortest = shortest,
                    .longest = longest,
                };
            }
        }

        /// Creates a map backed by memory allocated with `allocator`.
        ///
        /// Keys are kept as pointers to externally-owned memory.
        ///
        /// Handles `kvs_list` the same way as `initComptime`.
        pub fn init(kvs_list: anytype, allocator: mem.Allocator) mem.Allocator.Error!Self {
            if (kvs_list.len == 0) return empty;
            if (kvs_list.len > std.math.maxInt(u32)) return error.OutOfMemory;

            const shortest, const longest, const chunks_len = lengthBounds(kvs_list) orelse
                return error.OutOfMemory;
            const kvs_len = kvs_list.len;
            const size = allocSize(kvs_len, chunks_len);
            const data = try allocator.alignedAlloc(u8, .fromByteUnits(alignment), size);
            const ks, const vs, const chunks = partitionsFromAlloc(data, kvs_len, chunks_len);
            populate(kvs_list, ks, vs, chunks, shortest);

            return .{
                .ks = ks.ptr,
                .vs = vs.ptr,
                .chunks = chunks.ptr,
                .shortest = shortest,
                .longest = longest,
            };
        }

        /// Frees the memory allocated by the map.
        ///
        /// This method should only be used with maps got from `init`
        /// and not from `initComptime`.
        pub fn deinit(self: Self, allocator: mem.Allocator) void {
            if (self.shortest > self.longest) return;

            const data = allocFromPartitions(
                self.keys(),
                self.values(),
                self.chunks[0 .. self.longest - self.shortest + @as(usize, 1)],
            );
            allocator.free(data);
        }

        /// Returns whether the map contains the given key.
        pub fn has(self: Self, key: []const u8) bool {
            return self.getIndex(key) != null;
        }

        /// Returns the corresponding value for the key if one exists,
        /// else `null`.
        ///
        /// If the key appears multiple times in the map, an arbitrary one
        /// of those is chosen.
        pub fn get(self: Self, key: []const u8) ?V {
            return if (self.getIndex(key)) |i| self.vs[i] else null;
        }

        /// Returns the index where the key is situated if one exists,
        /// else `null`.
        ///
        /// If the key appears multiple times in the map, an arbitrary one
        /// of those is chosen.
        pub fn getIndex(self: Self, key: []const u8) ?usize {
            if (key.len < self.shortest or key.len > self.longest) return null;

            const c = key.len - self.shortest;
            const start = if (c == 0) 0 else self.chunks[c - 1];
            const end = self.chunks[c];

            for (start..end) |i| {
                if (eql(self.ks[i], key)) return i;
            }
            return null;
        }

        /// Returns the key-value pair corresponding to a key which is a longest
        /// prefix of `str`.
        ///
        /// If multiple longest prefixes exist, an arbitrary one of those is
        /// chosen.
        pub fn getLongestPrefix(self: Self, str: []const u8) ?KV {
            return if (self.getLongestPrefixIndex(str)) |i| .{
                .key = self.ks[i],
                .value = self.vs[i],
            } else null;
        }

        /// Returns the index of a key-value pair whose key is a longest
        /// prefix of `str`.
        ///
        /// If multiple longest prefixes exist, an arbitrary one of those is
        /// chosen.
        pub fn getLongestPrefixIndex(self: Self, str: []const u8) ?usize {
            if (self.longest < self.shortest) return null;
            if (str.len < self.shortest) return null;

            const c = @min(str.len, self.longest) - self.shortest;
            var i = self.chunks[c];
            while (i > 0) {
                i -= 1;
                const key = self.ks[i];
                if (eql(key, str[0..key.len])) return i;
            }
            return null;
        }

        /// Keys of the map. Valid until `deinit` call.
        pub fn keys(self: Self) []const []const u8 {
            return self.ks[0..self.count()];
        }

        /// Values of the map. Valid until `deinit` call.
        pub fn values(self: Self) []const V {
            return self.vs[0..self.count()];
        }

        /// Number of entries in the map.
        pub fn count(self: Self) u32 {
            if (self.longest < self.shortest) return 0;
            return self.chunks[self.longest - self.shortest];
        }

        const Self = @This();

        const empty: Self = .{
            .ks = @ptrCast(&stub),
            .vs = @ptrCast(&stub),
            .chunks = @ptrCast(&stub),
            .shortest = 1,
            .longest = 0,
        };

        /// Pointers to `stub` are definitely non-`null`, non-`undefined`,
        /// well-aligned, and derefencable - so they can be cast to
        /// `[*]const T`s (where `T`'s alignment is not greater than
        /// `alignment`) and be sliced with `0..0` bounds.
        ///
        /// The simpler `&.{}` does not seem to currently guarantee all
        /// the points above.
        const stub: u8 align(alignment) = 0;

        fn lengthBounds(kvs_list: anytype) ?struct { u32, u32, usize } {
            var min = kvs_list[0][0].len;
            var max = kvs_list[0][0].len;
            for (kvs_list) |kv| {
                min = @min(min, kv[0].len);
                max = @max(max, kv[0].len);
            }
            if (max > std.math.maxInt(u32)) return null;
            return .{ @intCast(min), @intCast(max), max - min + 1 };
        }

        fn populate(
            kvs_list: anytype,
            ks: [][]const u8,
            vs: []V,
            chunks: []u32,
            shortest: u32,
        ) void {
            @memset(chunks, 0);
            for (kvs_list, ks, vs) |kv, *k, *v| {
                k.* = kv[0];
                v.* = if (V == void) {} else kv[1];
                chunks[kv[0].len - shortest] += 1;
            }
            var tot: u32 = 0;
            for (chunks) |*c| {
                tot += c.*;
                c.* = tot;
            }
            const Context = struct {
                keys: [][]const u8,
                vals: []V,

                pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
                    return ctx.keys[a].len < ctx.keys[b].len;
                }

                pub fn swap(ctx: @This(), a: usize, b: usize) void {
                    std.mem.swap([]const u8, &ctx.keys[a], &ctx.keys[b]);
                    std.mem.swap(V, &ctx.vals[a], &ctx.vals[b]);
                }
            };
            const ctx: Context = .{ .keys = ks, .vals = vs };
            mem.sortUnstableContext(0, ks.len, ctx);
        }

        const alignment = @max(@alignOf([]const u8), @alignOf(V), @alignOf(u32));

        fn allocSize(kvs_len: usize, chunks_len: usize) usize {
            return kvs_len * (@sizeOf([]const u8) + @sizeOf(V)) + chunks_len * @sizeOf(u32);
        }

        /// Partition an allocation into `ks`, `vs`, and `chunks`.
        fn partitionsFromAlloc(
            data: []align(alignment) u8,
            kvs_len: usize,
            chunks_len: usize,
        ) struct { [][]const u8, []V, []u32 } {
            std.debug.assert(data.len == allocSize(kvs_len, chunks_len));

            const ks_sz = kvs_len * @sizeOf([]const u8);
            const vs_sz = kvs_len * @sizeOf(V);
            const ch_sz = chunks_len * @sizeOf(u32);

            const ks_al = @alignOf([]const u8);
            const vs_al = @alignOf(V);
            const ch_al = @alignOf(u32);

            // partitions' ordering:
            // - primary: descending alignment
            // - secondary: `ks`, `vs`, `chunks`
            const ks_offset, const vs_offset, const ch_offset = if (ks_al == alignment)
                if (vs_al >= ch_al) .{ 0, ks_sz, ks_sz + vs_sz } else .{ 0, ks_sz + ch_sz, ks_sz }
            else if (vs_al == alignment)
                if (ks_al >= ch_al) .{ vs_sz, 0, vs_sz + ks_sz } else .{ vs_sz + ch_sz, 0, vs_sz }
            else if (ks_al >= vs_al)
                .{ ch_sz, ch_sz + ks_sz, 0 }
            else
                .{ ch_sz + vs_sz, ch_sz, 0 };

            return .{
                @ptrCast(@alignCast(data[ks_offset..][0..ks_sz])),
                @ptrCast(@alignCast(data[vs_offset..][0..vs_sz])),
                @ptrCast(@alignCast(data[ch_offset..][0..ch_sz])),
            };
        }

        /// Reconstruct an allocation from `ks`, `vs`, and `chunks`.
        fn allocFromPartitions(
            ks: []const []const u8,
            vs: []const V,
            chunks: []const u32,
        ) []align(alignment) const u8 {
            std.debug.assert(ks.len == vs.len);

            const ptr: [*]align(alignment) const u8 = if (@alignOf([]const u8) == alignment)
                @ptrCast(@alignCast(ks.ptr))
            else if (@alignOf(V) == alignment)
                @ptrCast(@alignCast(vs.ptr))
            else
                @ptrCast(@alignCast(chunks.ptr));
            return ptr[0..allocSize(ks.len, chunks.len)];
        }
    };
}

const TestEnum = enum { A, B, C, D, E };
const TestMap = StaticStringMap(TestEnum);
const TestKV = struct { []const u8, TestEnum };
const TestMapVoid = StaticStringMap(void);
const TestKVVoid = struct { []const u8 };
const TestMapWithEql = StaticStringMapWithEql(TestEnum, eqlAsciiIgnoreCase);
const testing = std.testing;
const test_alloc = testing.allocator;

test "list literal of list literals" {
    const slice: []const TestKV = &.{
        .{ "these", .D },
        .{ "have", .A },
        .{ "nothing", .B },
        .{ "incommon", .C },
        .{ "samelen", .E },
    };

    const map = TestMap.initComptime(slice);
    try testMap(map);
    // Default comparison is case sensitive
    try testing.expect(null == map.get("NOTHING"));

    // runtime init(), deinit()
    const map_rt = try TestMap.init(slice, test_alloc);
    defer map_rt.deinit(test_alloc);
    try testMap(map_rt);
    // Default comparison is case sensitive
    try testing.expect(null == map_rt.get("NOTHING"));
}

test "array of structs" {
    const slice = [_]TestKV{
        .{ "these", .D },
        .{ "have", .A },
        .{ "nothing", .B },
        .{ "incommon", .C },
        .{ "samelen", .E },
    };

    try testMap(TestMap.initComptime(slice));
}

test "slice of structs" {
    const slice = [_]TestKV{
        .{ "these", .D },
        .{ "have", .A },
        .{ "nothing", .B },
        .{ "incommon", .C },
        .{ "samelen", .E },
    };

    try testMap(TestMap.initComptime(slice));
}

fn testMap(map: anytype) !void {
    try testing.expectEqual(TestEnum.A, map.get("have").?);
    try testing.expectEqual(TestEnum.B, map.get("nothing").?);
    try testing.expect(null == map.get("missing"));
    try testing.expectEqual(TestEnum.D, map.get("these").?);
    try testing.expectEqual(TestEnum.E, map.get("samelen").?);

    try testing.expect(!map.has("missing"));
    try testing.expect(map.has("these"));

    try testing.expect(null == map.get(""));
    try testing.expect(null == map.get("averylongstringthathasnomatches"));
}

test "void value type, slice of structs" {
    const slice = [_]TestKVVoid{
        .{"these"},
        .{"have"},
        .{"nothing"},
        .{"incommon"},
        .{"samelen"},
    };
    const map = TestMapVoid.initComptime(slice);
    try testSet(map);
    // Default comparison is case sensitive
    try testing.expect(null == map.get("NOTHING"));
}

test "void value type, list literal of list literals" {
    const slice = [_]TestKVVoid{
        .{"these"},
        .{"have"},
        .{"nothing"},
        .{"incommon"},
        .{"samelen"},
    };

    try testSet(TestMapVoid.initComptime(slice));
}

fn testSet(map: TestMapVoid) !void {
    try testing.expectEqual({}, map.get("have").?);
    try testing.expectEqual({}, map.get("nothing").?);
    try testing.expect(null == map.get("missing"));
    try testing.expectEqual({}, map.get("these").?);
    try testing.expectEqual({}, map.get("samelen").?);

    try testing.expect(!map.has("missing"));
    try testing.expect(map.has("these"));

    try testing.expect(null == map.get(""));
    try testing.expect(null == map.get("averylongstringthathasnomatches"));
}

fn testStaticStringMapWithEql(map: TestMapWithEql) !void {
    try testMap(map);
    try testing.expectEqual(TestEnum.A, map.get("HAVE").?);
    try testing.expectEqual(TestEnum.E, map.get("SameLen").?);
    try testing.expect(null == map.get("SameLength"));
    try testing.expect(map.has("ThESe"));
}

test "StaticStringMapWithEql" {
    const slice = [_]TestKV{
        .{ "these", .D },
        .{ "have", .A },
        .{ "nothing", .B },
        .{ "incommon", .C },
        .{ "samelen", .E },
    };

    try testStaticStringMapWithEql(TestMapWithEql.initComptime(slice));
}

test "empty" {
    const m1 = StaticStringMap(usize).initComptime(.{});
    try testing.expect(null == m1.get("anything"));

    const m2 = StaticStringMapWithEql(usize, eqlAsciiIgnoreCase).initComptime(.{});
    try testing.expect(null == m2.get("anything"));

    const m3 = try StaticStringMap(usize).init(.{}, test_alloc);
    try testing.expect(null == m3.get("anything"));

    const m4 = try StaticStringMapWithEql(usize, eqlAsciiIgnoreCase).init(.{}, test_alloc);
    try testing.expect(null == m4.get("anything"));
}

test "redundant entries" {
    const slice = [_]TestKV{
        .{ "redundant", .D },
        .{ "theNeedle", .A },
        .{ "redundant", .B },
        .{ "re" ++ "dundant", .C },
        .{ "redun" ++ "dant", .E },
    };
    const map = TestMap.initComptime(slice);

    // No promises about which one you get:
    try testing.expect(null != map.get("redundant"));

    // Default map is not case sensitive:
    try testing.expect(null == map.get("REDUNDANT"));

    try testing.expectEqual(TestEnum.A, map.get("theNeedle").?);
}

test "redundant insensitive" {
    const slice = [_]TestKV{
        .{ "redundant", .D },
        .{ "theNeedle", .A },
        .{ "redundanT", .B },
        .{ "RE" ++ "dundant", .C },
        .{ "redun" ++ "DANT", .E },
    };

    const map = TestMapWithEql.initComptime(slice);

    // No promises about which result you'll get ...
    try testing.expect(null != map.get("REDUNDANT"));
    try testing.expect(null != map.get("ReDuNdAnT"));
    try testing.expectEqual(TestEnum.A, map.get("theNeedle").?);
}

test "comptime-only value" {
    const map = StaticStringMap(type).initComptime(.{
        .{ "a", struct {
            pub const foo = 1;
        } },
        .{ "b", struct {
            pub const foo = 2;
        } },
        .{ "c", struct {
            pub const foo = 3;
        } },
    });

    try testing.expect(map.get("a").?.foo == 1);
    try testing.expect(map.get("b").?.foo == 2);
    try testing.expect(map.get("c").?.foo == 3);
    try testing.expect(map.get("d") == null);
}

test "getLongestPrefix" {
    const slice = [_]TestKV{
        .{ "a", .A },
        .{ "aa", .B },
        .{ "aaa", .C },
        .{ "aaaa", .D },
    };

    const map = TestMap.initComptime(slice);

    try testing.expectEqual(null, map.getLongestPrefix(""));
    try testing.expectEqual(null, map.getLongestPrefix("bar"));
    try testing.expectEqualStrings("aaaa", map.getLongestPrefix("aaaabar").?.key);
    try testing.expectEqualStrings("aaa", map.getLongestPrefix("aaabar").?.key);
}

test "getLongestPrefix2" {
    const slice = [_]struct { []const u8, u8 }{
        .{ "one", 1 },
        .{ "two", 2 },
        .{ "three", 3 },
        .{ "four", 4 },
        .{ "five", 5 },
        .{ "six", 6 },
        .{ "seven", 7 },
        .{ "eight", 8 },
        .{ "nine", 9 },
    };
    const map = StaticStringMap(u8).initComptime(slice);

    try testing.expectEqual(1, map.get("one"));
    try testing.expectEqual(null, map.get("o"));
    try testing.expectEqual(null, map.get("onexxx"));
    try testing.expectEqual(9, map.get("nine"));
    try testing.expectEqual(null, map.get("n"));
    try testing.expectEqual(null, map.get("ninexxx"));
    try testing.expectEqual(null, map.get("xxx"));

    try testing.expectEqual(1, map.getLongestPrefix("one").?.value);
    try testing.expectEqual(1, map.getLongestPrefix("onexxx").?.value);
    try testing.expectEqual(null, map.getLongestPrefix("o"));
    try testing.expectEqual(null, map.getLongestPrefix("on"));
    try testing.expectEqual(9, map.getLongestPrefix("nine").?.value);
    try testing.expectEqual(9, map.getLongestPrefix("ninexxx").?.value);
    try testing.expectEqual(null, map.getLongestPrefix("n"));
    try testing.expectEqual(null, map.getLongestPrefix("xxx"));
}

test "sorting kvs doesn't exceed eval branch quota" {
    // from https://github.com/ziglang/zig/issues/19803
    const TypeToByteSizeLUT = std.StaticStringMap(u32).initComptime(.{
        .{ "bool", 0 },
        .{ "c_int", 0 },
        .{ "c_long", 0 },
        .{ "c_longdouble", 0 },
        .{ "t20", 0 },
        .{ "t19", 0 },
        .{ "t18", 0 },
        .{ "t17", 0 },
        .{ "t16", 0 },
        .{ "t15", 0 },
        .{ "t14", 0 },
        .{ "t13", 0 },
        .{ "t12", 0 },
        .{ "t11", 0 },
        .{ "t10", 0 },
        .{ "t9", 0 },
        .{ "t8", 0 },
        .{ "t7", 0 },
        .{ "t6", 0 },
        .{ "t5", 0 },
        .{ "t4", 0 },
        .{ "t3", 0 },
        .{ "t2", 0 },
        .{ "t1", 1 },
    });
    try testing.expectEqual(1, TypeToByteSizeLUT.get("t1"));
}
