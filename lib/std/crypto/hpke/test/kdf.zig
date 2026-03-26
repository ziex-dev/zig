const std = @import("std");
const kdf = @import("../kdf.zig");

fn testLabeledExtractExpand(comptime labeledExtract: anytype, comptime labeledExpand: anytype, comptime hash_len: usize) !void {
    const suite_id = "HPKE-v1";
    const label = "test";
    const salt = "salt";
    const ikm = "ikm";
    const info = "info";

    var prk_buf: [hash_len]u8 = undefined;
    var prk_len: usize = 0;
    try labeledExtract(salt, ikm, label, suite_id, &prk_buf, &prk_len);
    try std.testing.expectEqual(hash_len, prk_len);

    var out_buf: [32]u8 = undefined;
    try labeledExpand(&prk_buf, info, label, suite_id, &out_buf);

    var out2_buf: [32]u8 = undefined;
    try labeledExpand(&prk_buf, info, label, suite_id, &out2_buf);
    try std.testing.expectEqualSlices(u8, &out_buf, &out2_buf);

    const diff_info = "diff";
    var out3_buf: [32]u8 = undefined;
    try labeledExpand(&prk_buf, diff_info, label, suite_id, &out3_buf);
    try std.testing.expect(!std.mem.eql(u8, &out_buf, &out3_buf));
}

test "KDF: labeledExtractSha256 / labeledExpandSha256" {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    try testLabeledExtractExpand(
        kdf.labeledExtractSha256,
        kdf.labeledExpandSha256,
        32,
    );
}

test "KDF: HkdfSha256Vtable" {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    const vtable = kdf.HkdfSha256Vtable;
    try testLabeledExtractExpand(
        vtable.labeledExtract,
        vtable.labeledExpand,
        32,
    );
}

test "KDF: HkdfSha384Vtable" {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    const vtable = kdf.HkdfSha384Vtable;
    try testLabeledExtractExpand(
        vtable.labeledExtract,
        vtable.labeledExpand,
        48,
    );
}

test "KDF: HkdfSha512Vtable" {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    const vtable = kdf.HkdfSha512Vtable;
    try testLabeledExtractExpand(
        vtable.labeledExtract,
        vtable.labeledExpand,
        64,
    );
}

test "KDF: labeledExtract with empty salt and ikm" {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    var out: [32]u8 = undefined;
    var out_len: usize = 0;
    try kdf.labeledExtractSha256(null, &[_]u8{}, "test", "HPKE-v1", &out, &out_len);
    try std.testing.expectEqual(32, out_len);
    var all_zero = true;
    for (out) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "KDF: labeledExpand with zero-length output" {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    var prk: [32]u8 = undefined;
    var prk_len: usize = 0;
    try kdf.labeledExtractSha256(null, &[_]u8{}, "test", "HPKE-v1", &prk, &prk_len);

    var out: [0]u8 = undefined;
    try kdf.labeledExpandSha256(&prk, "info", "test", "HPKE-v1", &out);
}
