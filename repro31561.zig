/// Regression test for #31561.
///
/// On Windows, `Dir.updateFile` calls `Atomic.replace` which renames a temp
/// file over the destination via `NtSetInformationFile`. Over UNC/loopback
/// paths (`\\127.0.0.1\C$\...`), the rename transiently returns
/// `ACCESS_DENIED` because a prior close has not fully propagated through
/// the SMB stack.
///
/// Reproduces reliably within a few runs before the fix. After the fix
/// (retry with exponential backoff in `dirRenameWindowsInner`), passes
/// consistently.
///
/// Run with the repo's stage3 compiler:
///   .\build-debug\stage3\bin\zig.exe test repro31561.zig --zig-lib-dir lib
///
/// To stress-test, run in a loop:
///   for ($i=0; $i -lt 20; $i++) { .\build-debug\stage3\bin\zig.exe test repro31561.zig --zig-lib-dir lib }
const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

test "issue 31561: updateFile over UNC path triggers ACCESS_DENIED" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var fd_path_buf: [Dir.max_path_bytes]u8 = undefined;
    const dir_path = fd_path_buf[0..try tmp.dir.realPath(io, &fd_path_buf)];

    const win_type = Dir.path.getWin32PathType(u8, dir_path);
    const unc_path = switch (win_type) {
        .drive_absolute => blk: {
            const pre = "\\\\127.0.0.1\\";
            var p = try Dir.path.joinZ(gpa, &.{ pre, dir_path });
            p[pre.len + 1] = '$';
            break :blk p;
        },
        else => return error.SkipZigTest,
    };
    defer gpa.free(unc_path);

    var unc_dir = Dir.openDirAbsolute(io, unc_path, .{}) catch {
        return error.SkipZigTest; // no admin share access
    };
    defer unc_dir.close(io);

    // Repeat the sequence many times to increase chance of hitting the race.
    for (0..100) |_| {
        try unc_dir.createDir(io, "subdir", .default_dir);

        const f = try unc_dir.createFile(io, "subdir/../file", .{});
        f.close(io);

        try unc_dir.copyFile("subdir/../file", unc_dir, "subdir/../copy", io, .{});
        try unc_dir.rename("subdir/../copy", unc_dir, "subdir/../rename", io);

        const rf = try unc_dir.openFile(io, "subdir/../rename", .{});
        rf.close(io);
        try unc_dir.deleteFile(io, "subdir/../rename");

        try unc_dir.writeFile(io, .{ .sub_path = "subdir/../update", .data = "something" });

        // This is the call that flakily returns AccessDenied before the fix.
        var dir = unc_dir;
        _ = try dir.updateFile(io, "subdir/../file", dir, "subdir/../update", .{});

        // Cleanup for next iteration.
        try unc_dir.deleteFile(io, "file");
        try unc_dir.deleteFile(io, "update");
        try unc_dir.deleteDir(io, "subdir");
    }
}
