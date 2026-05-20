const std = @import("std");
const Allocator = std.mem.Allocator;
const Ast = std.zig.Ast;
const Zir = std.zig.Zir;
const print = std.zig.Zir.print;

const Zcu = @import("Zcu.zig");

/// Write human-readable, debug formatted ZIR code.
pub const renderAsText = print.renderAsText;

pub fn renderInstructionContext(
    gpa: Allocator,
    block: []const Zir.Inst.Index,
    block_index: usize,
    scope_file: *Zcu.File,
    parent_decl_node: Ast.Node.Index,
    indent: u32,
    bw: *std.Io.Writer,
) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var writer: print.Writer = .{
        .gpa = gpa,
        .arena = arena.allocator(),
        .tree = scope_file.tree,
        .code = scope_file.zir.?,
        .indent = if (indent < 2) 2 else indent,
        .parent_decl_node = parent_decl_node,
        .recurse_decls = false,
        .recurse_blocks = true,
    };

    try writer.writeBody(bw, block[0..block_index]);
    try bw.splatByteAll(' ', writer.indent - 2);
    try bw.print("> %{d} ", .{@intFromEnum(block[block_index])});
    try writer.writeInstToStream(bw, block[block_index]);
    try bw.writeByte('\n');
    if (block_index + 1 < block.len) {
        try writer.writeBody(bw, block[block_index + 1 ..]);
    }
}

pub fn renderSingleInstruction(
    gpa: Allocator,
    inst: Zir.Inst.Index,
    scope_file: *Zcu.File,
    parent_decl_node: Ast.Node.Index,
    indent: u32,
    bw: *std.Io.Writer,
) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var writer: print.Writer = .{
        .gpa = gpa,
        .arena = arena.allocator(),
        .tree = scope_file.tree,
        .code = scope_file.zir.?,
        .indent = indent,
        .parent_decl_node = parent_decl_node,
        .recurse_decls = false,
        .recurse_blocks = false,
    };

    try bw.print("%{d} ", .{@intFromEnum(inst)});
    try writer.writeInstToStream(bw, inst);
}
