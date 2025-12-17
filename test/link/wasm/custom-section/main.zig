const std = @import("std");
const mem = std.mem;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;

const wasm_path = @import("build_options").wasm_path;

/// First, parse the custom sections from the `lib.zig` wasm binary.
/// Second, assert that the expected custom sections were in the wasm binary.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const wasm_bytes = try std.fs.cwd().readFileAlloc(wasm_path, allocator, .unlimited);
    defer allocator.free(wasm_bytes);

    var custom_sections = try get_custom_sections(wasm_bytes, allocator);
    defer custom_sections.deinit();

    std.debug.assert(custom_sections.count() == 3);

    const utf8_section = custom_sections.get("test-utf8").?;
    const non_utf8_section = custom_sections.get("test-non-utf8").?;

    const dupe_section = custom_sections.get("dupe-name").?;

    std.debug.assert(utf8_section.items.len == 1);
    std.debug.assert(std.mem.eql(u8, utf8_section.items[0], "abcd"));

    std.debug.assert(non_utf8_section.items.len == 1);
    std.debug.assert(std.mem.eql(u8, non_utf8_section.items[0], "\x00\x01\x02"));

    // TODO: Comment this back in and remove the "onetwo" assertion below.
    // std.debug.assert(dupe_section.items.len == 2);
    // std.debug.assert(std.mem.eql(u8, dupe_section.items[0], "one"));
    // std.debug.assert(std.mem.eql(u8, dupe_section.items[1], "two"));

    // TODO:
    //  When we have two `linksection`s with the same name we want there to be two custom sections.
    //  Instead, currently, one custom sections get emitted and the custom section contains both
    //  byte arrays.
    //  We should delete this assertion below and uncomment the assertions above, then modify
    //  `std/zig/llvm/{Builder,bitcode_writer}.zig` such that the duplicate custom sections do
    //  not get combined into one custom section.
    std.debug.assert(std.mem.eql(u8, dupe_section.items[0], "onetwo"));

    var iterator = custom_sections.iterator();
    while (iterator.next()) |data_list| {
        data_list.value_ptr.deinit(allocator);
    }
}


/// Note that multiple custom sections can have the same name, hence returning a `Map<Name, List<Data>>`.
fn get_custom_sections(
    wasm: []const u8,
    allocator: std.mem.Allocator
) !StringHashMap(ArrayList([]const u8)) {
    var map = std.StringHashMap(ArrayList([]const u8)).init(allocator);

    var idx: usize = 0;
    const custom_section_id = 0;

    const wasm_magic_number = &[_]u8 { 0x00, 0x61, 0x73, 0x6D };

    std.debug.assert(std.mem.eql(u8, wasm[0..4], wasm_magic_number));

    // Skip the magic number bytes
    idx += 4;

    // Skip the wasm version bytes
    idx += 4;

    while (idx < wasm.len) {
        const section_id = wasm[idx];

        // Skip the section id
        idx += 1;

        const section_leb = decodeLebU32(wasm[idx..idx+5]);
        const section_len = section_leb.num;

        // Skip the bytes used to encode the section's length.
        idx += section_leb.byte_count;

        if (section_id == custom_section_id) {
            var i = idx;

            const name_leb = decodeLebU32(wasm[i..i+5]);
            const name_len = name_leb.num;

            // Skip the bytes used to encode the name's length.
            i += name_leb.byte_count;

            const name = wasm[i..i+name_len];

            // Skip the name
            i += name_len;

            // Get the remaining bytes in the section.
            const data_len = section_len - name_leb.byte_count - name_len;
            const data = wasm[i..i+data_len];

            var entry = try map.getOrPut(name);
            if (!entry.found_existing) {
                entry.value_ptr.* = .empty;
            }

            try entry.value_ptr.append(allocator, data);
        }

        std.debug.assert(section_len > 0);
        // Skip to the next section.
        idx += section_len;
    }

    return map;
}

/// Decode an unsigned LEB128 encoded `u32`.
fn decodeLebU32(slice: []const u8) struct { num: u32, byte_count: usize  } {
    var decoded: u32 = 0;

    for (0..5) |idx| {
        const shift: u5 = @intCast(idx * 7);

        const byte: u8 = slice[idx];
        const lower_7_bits: u32 = (byte & 0x7F);

        const shifted_bits: u32 = lower_7_bits << shift;

        decoded = decoded | shifted_bits;

        const highest_bit = byte & 0x80;
        if (highest_bit == 0) {
            return .{ .num = decoded, .byte_count = idx + 1 };
        }
    }

    unreachable;
}
