//! This allocator takes an existing allocator, wraps it, and provides an interface where
//! you can allocate and then free it all together. Calls to free an individual item only
//! free the item if it was the most recent allocation, otherwise calls to free do
//! nothing.
//!
//! The `Allocator` implementation provided is threadsafe, given that `child_allocator`
//! is threadsafe as well.
const ArenaAllocator = @This();

child_allocator: Allocator,
state: State,

/// Inner state of ArenaAllocator. Can be stored rather than the entire ArenaAllocator
/// as a memory-saving optimization.
///
/// Default initialization of this struct is deprecated; use `init` instead.
pub const State = struct {
    first_node: ?*Node = null,

    pub const init: State = .{ .first_node = null };

    pub fn promote(state: State, child_allocator: Allocator) ArenaAllocator {
        return .{
            .child_allocator = child_allocator,
            .state = state,
        };
    }
};

pub fn allocator(arena: *ArenaAllocator) Allocator {
    return .{
        .ptr = arena,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

pub fn init(child_allocator: Allocator) ArenaAllocator {
    return State.init.promote(child_allocator);
}

/// Not threadsafe.
pub fn deinit(arena: ArenaAllocator) void {
    // NOTE: When changing this, make sure `reset()` is adjusted accordingly!

    var it = arena.state.first_node;
    while (it) |node| {
        // this has to occur before the free because the free frees node
        it = node.next;
        const allocated_slice = @as([*]u8, @ptrCast(node))[0 .. node.tagged_size & ~Node.resize_mask];
        arena.child_allocator.rawFree(allocated_slice, .of(Node), @returnAddress());
    }
}

/// Queries the current memory use of this arena.
/// This will **not** include the storage required for internal keeping.
///
/// Not threadsafe.
pub fn queryCapacity(arena: ArenaAllocator) usize {
    var size: usize = 0;
    var it = arena.state.first_node;
    while (it) |node| : (it = node.next) {
        // Compute the actually allocated size excluding the
        // linked list node.
        size += (node.tagged_size & ~Node.resize_mask) - @sizeOf(Node);
    }
    return size;
}

pub const ResetMode = union(enum) {
    /// Releases all allocated memory in the arena.
    free_all,
    /// This will pre-heat the arena for future allocations by allocating a
    /// large enough buffer for all previously done allocations.
    /// Preheating will speed up the allocation process by invoking the backing allocator
    /// less often than before. If `reset()` is used in a loop, this means that after the
    /// biggest operation, no memory allocations are performed anymore.
    retain_capacity,
    /// This is the same as `retain_capacity`, but the memory will be shrunk to
    /// this value if it exceeds the limit.
    retain_with_limit: usize,
};
/// Resets the arena allocator and frees all allocated memory.
///
/// `mode` defines how the currently allocated memory is handled.
/// See the variant documentation for `ResetMode` for the effects of each mode.
///
/// The function will return whether the reset operation was successful or not.
/// If the reallocation  failed `false` is returned. The arena will still be fully
/// functional in that case, all memory is released. Future allocations just might
/// be slower.
///
/// Not threadsafe.
///
/// NOTE: If `mode` is `free_all`, the function will always return `true`.
pub fn reset(arena: *ArenaAllocator, mode: ResetMode) bool {
    // Some words on the implementation:
    // The reset function can be implemented with two basic approaches:
    // - Counting how much bytes were allocated since the last reset, and storing that
    //   information in State. This will make reset fast and alloc only a teeny tiny bit
    //   slower.
    // - Counting how much bytes were allocated by iterating the chunk linked list. This
    //   will make reset slower, but alloc() keeps the same speed when reset() as if reset()
    //   would not exist.
    //
    // The second variant was chosen for implementation, as with more and more calls to reset(),
    // the function will get faster and faster. At one point, the complexity of the function
    // will drop to amortized O(1), as we're only ever having a single chunk that will not be
    // reallocated, and we're not even touching the backing allocator anymore.
    //
    // Thus, only the first hand full of calls to reset() will actually need to iterate the linked
    // list, all future calls are just taking the first node, and only resetting the `end_index`
    // value.
    const requested_capacity = switch (mode) {
        .retain_capacity => arena.queryCapacity(),
        .retain_with_limit => |limit| @min(limit, arena.queryCapacity()),
        .free_all => 0,
    };
    if (requested_capacity == 0) {
        // just reset when we don't have anything to reallocate
        arena.deinit();
        arena.state = .init;
        return true;
    }
    const total_size = mem.alignForward(usize, @sizeOf(Node) + requested_capacity, 2);
    // Free all nodes except for the last one
    var it = arena.state.first_node;
    const first_node: *Node = while (it) |node| {
        // this has to occur before the free because the free frees node
        it = node.next;
        if (it == null) break node;
        const allocated_slice = @as([*]u8, @ptrCast(node))[0 .. node.tagged_size & ~Node.resize_mask];
        arena.child_allocator.rawFree(allocated_slice, .of(Node), @returnAddress());
    } else {
        return true;
    };
    // reset the state before we try resizing the buffers, so we definitely have reset the arena to 0.
    first_node.end_index = 0;
    arena.state.first_node = first_node;
    var allocated_slice = @as([*]u8, @ptrCast(first_node))[0 .. first_node.tagged_size & ~Node.resize_mask];
    if (allocated_slice.len == total_size) {
        // perfect, no need to invoke the child_allocator
        return true;
    }
    if (arena.child_allocator.rawResize(allocated_slice, .of(Node), total_size, @returnAddress())) {
        // successful resize
        first_node.tagged_size = total_size;
        allocated_slice.len = total_size;
    } else {
        // manual realloc
        const new_ptr = arena.child_allocator.rawAlloc(total_size, .of(Node), @returnAddress()) orelse {
            // we failed to preheat the arena properly, signal this to the user.
            return false;
        };
        arena.child_allocator.rawFree(allocated_slice, .of(Node), @returnAddress());
        const new_first_node: *Node = @ptrCast(@alignCast(new_ptr));
        new_first_node.* = .init(total_size, null);
        arena.state.first_node = new_first_node;
    }
    return true;
}

const Node = struct {
    tagged_size: usize,
    end_index: usize,
    next: ?*Node = null,

    fn init(size: usize, next: ?*Node) Node {
        assert(size & resize_mask == 0);
        return .{ .tagged_size = size, .end_index = 0, .next = next };
    }

    const resize_mask: usize = 1;

    /// Returns allocated slice or `null` if another resize is already in progress.
    fn beginResize(node: *Node) ?[]u8 {
        const tagged_size = @atomicRmw(usize, &node.tagged_size, .Or, resize_mask, .acquire);
        if (tagged_size & resize_mask != 0) return null;
        return @as([*]u8, @ptrCast(node))[0 .. tagged_size & ~resize_mask];
    }
    /// `new_size` has to be aligned to a 2-byte boundary (an even number).
    fn endResize(node: *Node, new_size: usize) void {
        assert(new_size & resize_mask == 0);
        @atomicStore(usize, &node.tagged_size, new_size, .release);
    }

    fn allocatedSlice(node: *Node) []u8 {
        // This can be `.monotonic` since we're only ever increasing the size of
        // a node, so if an out-of-date value is loaded the worst that can happen
        // is that some `alloc` call creates another node prematurely or that a
        // `resize` call fails to grow an allocation even though it could.
        // In both cases the chances are very high that the `alloc` call that
        // caused the node size to increase in the first place will just use the
        // memory it's requested for itself anyway, so it's very unlikely that
        // any memory will be wasted in this very rare and unlucky scenario.
        const tagged_size = @atomicLoad(usize, &node.tagged_size, .monotonic);
        return @as([*]u8, @ptrCast(node))[0 .. tagged_size & ~resize_mask];
    }
};

fn alloc(ctx: *anyopaque, n: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    const arena: *ArenaAllocator = @ptrCast(@alignCast(ctx));
    _ = ret_addr;

    const ptr_align = alignment.toByteUnits();

    const first_node: ?*Node, const prev_size: usize = first_node: {
        const node = @atomicLoad(?*Node, &arena.state.first_node, .acquire) orelse
            break :first_node .{ null, 0 };
        var cur_end_index = @atomicLoad(usize, &node.end_index, .monotonic);
        while (true) {
            var cur_buf = node.allocatedSlice()[@sizeOf(Node)..];
            const aligned_index = cur_end_index +
                mem.alignPointerOffset(cur_buf.ptr + cur_end_index, ptr_align).?;

            if (aligned_index + n > cur_buf.len) {
                var allocated_slice = node.beginResize() orelse {
                    // Unfortunately another thread is already resizing. We have
                    // to cut our losses and proceed as if the resize wasn't
                    // successful. We need a new node!
                    break :first_node .{ node, cur_buf.len };
                };
                defer node.endResize(allocated_slice.len);

                const bigger_size = mem.alignForward(usize, @sizeOf(Node) + aligned_index + n, 2);
                assert(bigger_size & Node.resize_mask == 0);
                if (arena.child_allocator.rawResize(allocated_slice, .of(Node), bigger_size, @returnAddress())) {
                    allocated_slice.len = bigger_size;
                    cur_buf = allocated_slice[@sizeOf(Node)..];
                } else {
                    break :first_node .{ node, allocated_slice.len - @sizeOf(Node) };
                }
            }

            cur_end_index = @cmpxchgWeak(
                usize,
                &node.end_index,
                cur_end_index,
                aligned_index + n,
                .monotonic,
                .monotonic,
            ) orelse {
                return cur_buf[aligned_index..][0..n].ptr;
            };
        }
    };

    const new_node: *Node = new_node: {
        const min_size = @sizeOf(Node) + ptr_align + n + 16;
        const big_enough_size = prev_size + min_size;
        const size = mem.alignForward(usize, big_enough_size + big_enough_size / 2, 2);
        assert(size & Node.resize_mask == 0);
        const ptr = arena.child_allocator.rawAlloc(size, .of(Node), @returnAddress()) orelse
            return null;
        const new_node: *Node = @ptrCast(@alignCast(ptr));
        new_node.* = .init(size, first_node);
        break :new_node new_node;
    };
    const new_buf = @as([*]u8, @ptrCast(new_node))[0..new_node.tagged_size][@sizeOf(Node)..];
    const aligned_index = mem.alignPointerOffset(new_buf.ptr, ptr_align).?;
    new_node.end_index = aligned_index + n;

    while (@cmpxchgWeak(
        ?*Node,
        &arena.state.first_node,
        new_node.next,
        new_node,
        .release,
        .monotonic,
    )) |old_first_node| {
        new_node.next = old_first_node;
    }

    return new_buf[aligned_index..][0..n].ptr;
}

fn resize(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
    const arena: *ArenaAllocator = @ptrCast(@alignCast(ctx));
    _ = alignment;
    _ = ret_addr;

    const node = @atomicLoad(?*Node, &arena.state.first_node, .acquire) orelse return false;
    const cur_buf_ptr = @as([*]u8, @ptrCast(node)) + @sizeOf(Node);

    var cur_end_index = @atomicLoad(usize, &node.end_index, .monotonic);
    while (true) {
        if (cur_buf_ptr + cur_end_index != buf.ptr + buf.len) {
            // It's not the most recent allocation, so it cannot be expanded,
            // but it's fine if they want to make it smaller.
            return new_len <= buf.len;
        }

        const new_end_index: usize = new_end_index: {
            if (buf.len >= new_len) {
                break :new_end_index cur_end_index - (buf.len - new_len);
            }
            const cur_buf_len = node.allocatedSlice().len - @sizeOf(Node);
            // Saturating arithmetic because `tagged_size` and `end_index` are
            // not guaranteed to be synced at this point.
            if (cur_buf_len -| cur_end_index >= new_len - buf.len) {
                break :new_end_index cur_end_index + (new_len - buf.len);
            }
            return false;
        };

        cur_end_index = @cmpxchgWeak(
            usize,
            &node.end_index,
            cur_end_index,
            new_end_index,
            .monotonic,
            .monotonic,
        ) orelse {
            return true;
        };
    }
}

fn remap(
    context: *anyopaque,
    memory: []u8,
    alignment: Alignment,
    new_len: usize,
    return_address: usize,
) ?[*]u8 {
    return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
}

fn free(ctx: *anyopaque, buf: []u8, alignment: Alignment, ret_addr: usize) void {
    const arena: *ArenaAllocator = @ptrCast(@alignCast(ctx));
    _ = alignment;
    _ = ret_addr;

    if (buf.len == 0) return; // TODO can this be an assert?

    const node = @atomicLoad(?*Node, &arena.state.first_node, .acquire).?;
    const cur_buf_ptr: [*]u8 = @as([*]u8, @ptrCast(node)) + @sizeOf(Node);

    var cur_end_index = @atomicLoad(usize, &node.end_index, .monotonic);
    while (true) {
        if (cur_buf_ptr + cur_end_index != buf.ptr + buf.len) {
            // Not the most recent allocation; we cannot free it.
            return;
        }
        cur_end_index = @cmpxchgWeak(
            usize,
            &node.end_index,
            cur_end_index,
            cur_end_index - buf.len,
            .monotonic,
            .monotonic,
        ) orelse {
            return;
        };
    }
}

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

test "reset with preheating" {
    var arena_allocator = ArenaAllocator.init(std.testing.allocator);
    defer arena_allocator.deinit();
    // provides some variance in the allocated data
    var rng_src = std.Random.DefaultPrng.init(std.testing.random_seed);
    const random = rng_src.random();
    var rounds: usize = 25;
    while (rounds > 0) {
        rounds -= 1;
        _ = arena_allocator.reset(.retain_capacity);
        var alloced_bytes: usize = 0;
        const total_size: usize = random.intRangeAtMost(usize, 256, 16384);
        while (alloced_bytes < total_size) {
            const size = random.intRangeAtMost(usize, 16, 256);
            const alignment: Alignment = .@"32";
            const slice = try arena_allocator.allocator().alignedAlloc(u8, alignment, size);
            try std.testing.expect(alignment.check(@intFromPtr(slice.ptr)));
            try std.testing.expectEqual(size, slice.len);
            alloced_bytes += slice.len;
        }
    }
}

test "reset while retaining a buffer" {
    var arena_allocator = ArenaAllocator.init(std.testing.allocator);
    defer arena_allocator.deinit();
    const a = arena_allocator.allocator();

    // Create two internal buffers
    _ = try a.alloc(u8, 1);
    _ = try a.alloc(u8, 1000);

    try std.testing.expect(arena_allocator.state.first_node != null);

    // Check that we have at least two buffers
    try std.testing.expect(arena_allocator.state.first_node.?.next != null);

    // This retains the first allocated buffer
    try std.testing.expect(arena_allocator.reset(.{ .retain_with_limit = 1 }));
    try std.testing.expect(arena_allocator.state.first_node.?.next == null);
}
