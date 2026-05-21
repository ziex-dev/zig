const std = @import("std");
const Dir = std.Io.Dir;
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const InstallDir = std.Build.InstallDir;
const CompileCommands = @This();
const assert = std.debug.assert;

pub const base_id: Step.Id = .compile_commands;

step: Step,
generated_json: std.Build.GeneratedFile,
fragment_dir: std.ArrayList(LazyPath) = .empty,

pub fn create(owner: *std.Build) *CompileCommands {
    const compile_commands = owner.allocator.create(CompileCommands) catch @panic("OOM");
    compile_commands.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = "Generate compile_commands.json",
            .owner = owner,
            .makeFn = make,
        }),
        .generated_json = .{ .step = &compile_commands.step },
    };
    return compile_commands;
}

pub fn addFragmentDir(compile_commands: *CompileCommands, owner: *std.Build, dir: LazyPath) void {
    // NOTE: This is a little redundant since the dependency chain for this step is:
    //       Step.CompileCommands -> Step.Compile (generates fragments with -MJ) -> Step.WriteFile (fragment Dir)
    //       This adds Step.CompileCommands -> Step.WriteFile (fragment Dir)
    //       However, there might be a valid edge case where there is no Step.Compile in the chain, in which
    //       case this whole chain ends up producing the empty (but valid) JSON "[]".
    dir.addStepDependencies(&compile_commands.step);
    compile_commands.fragment_dir.append(owner.allocator, dir) catch @panic("OOM");
}

pub fn getMergedJson(compile_commands: *CompileCommands) LazyPath {
    return .{ .generated = .{ .file = &compile_commands.generated_json } };
}

fn make(step: *Step, options: Step.MakeOptions) !void {
    _ = options;
    const b = step.owner;
    const io = b.graph.io;
    const arena = b.allocator;
    const compile_commands: *CompileCommands = @fieldParentPtr("step", step);

    // We do not know the final output paths yet, use a temp path to store compile_commands.json
    var rand_int: u64 = undefined;
    io.random(@ptrCast(&rand_int));
    const tmp_dir_path = "tmp" ++ Dir.path.sep_str ++ std.fmt.hex(rand_int);
    try b.cache_root.handle.createDirPath(io, tmp_dir_path);
    const full_path = try b.cache_root.join(arena, &.{ tmp_dir_path, "compile_commands.json" });
    compile_commands.generated_json.path = full_path;

    const fh = try std.Io.Dir.createFileAbsolute(io, full_path, .{});
    defer fh.close(io);
    var wbuf: [1024]u8 = undefined;
    var fhw = fh.writer(io, &wbuf);
    try fhw.interface.writeByte('[');

    var need_comma: bool = false;
    for (compile_commands.fragment_dir.items) |fdir_lazy| {
        const fragment_p = try fdir_lazy.getPath4(b, null);
        const fragment_dir_real = try fragment_p.root_dir.handle.openDir(io, fragment_p.sub_path, .{ .iterate = true });
        defer fragment_dir_real.close(io);

        var diter = fragment_dir_real.iterate();
        while (try diter.next(io)) |entry| {
            if (need_comma) {
                try fhw.interface.writeByte(',');
            }
            // Should only be fragment files in our temp dir since we have exclusive ownership
            assert(entry.kind == .file);
            const fragment_fh = try fragment_dir_real.openFile(io, entry.name, .{});
            var rdbuf: [1024]u8 = undefined;
            var fragment_fr = fragment_fh.reader(io, &rdbuf);

            // Stream the entire fragment into the output file, stripping the newline chars + comma at the end since
            // we're manually handling comma separation in the merged JSON ourselves
            var written: usize = 0;
            while (true) {
                fragment_fr.interface.fill(rdbuf.len) catch |e| switch (e) {
                    error.EndOfStream => {
                        const slice = std.mem.trimEnd(u8, fragment_fr.interface.buffered(), "\r\n,");
                        try fhw.interface.writeAll(slice);
                        break;
                    },
                    else => return e,
                };
                try fhw.interface.writeAll(fragment_fr.interface.buffered());
                written += fragment_fr.interface.buffered().len;
                fragment_fr.interface.tossBuffered();
            }
            // If for some reason we get an output file with no JSON content (newlines/comma only), we will form invalid JSON by having "{...},,"".
            // There should be no way for this to happen, so make sure of that in debug mode.
            assert(written > 0);
            need_comma = true;
        }
    }
    try fhw.interface.writeByte(']');
    try fhw.interface.flush();

}
