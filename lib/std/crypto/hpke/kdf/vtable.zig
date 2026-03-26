//! KDF vtable definition for runtime dispatch.

const HpkeError = @import("../errors.zig").HpkeError;

pub const KdfVtable = struct {
    hash_len: usize,
    labeledExtract: *const fn (salt: ?[]const u8, ikm: []const u8, label: []const u8, suite_id: []const u8, out: []u8, out_len: *usize) HpkeError!void,
    labeledExpand: *const fn (prk: []const u8, info: []const u8, label: []const u8, suite_id: []const u8, out: []u8) HpkeError!void,
};
