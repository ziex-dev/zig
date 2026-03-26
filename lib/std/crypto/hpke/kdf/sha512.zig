//! HKDF-SHA512 vtable.

const std = @import("std");
const crypto = std.crypto;
const HpkeError = @import("../errors.zig").HpkeError;
const KdfVtable = @import("vtable.zig").KdfVtable;
const HmacSha512 = crypto.auth.hmac.Hmac(crypto.hash.sha2.Sha512);
const HkdfSha512 = crypto.kdf.hkdf.Hkdf(HmacSha512);

fn buildLabeled(parts: []const []const u8, out: []u8) usize {
    var pos: usize = 0;
    for (parts) |part| {
        @memcpy(out[pos..][0..part.len], part);
        pos += part.len;
    }
    return pos;
}

fn totalLength(parts: []const []const u8) usize {
    var total: usize = 0;
    for (parts) |part| total += part.len;
    return total;
}

fn labeledExtractImpl(
    salt: ?[]const u8,
    ikm: []const u8,
    label: []const u8,
    suite_id: []const u8,
    out: []u8,
    out_len: *usize,
) HpkeError!void {
    const parts = [_][]const u8{ "HPKE-v1", suite_id, label, ikm };
    if (totalLength(&parts) > 512) {
        return error.InputTooLong;
    }
    var buf: [512]u8 = undefined;
    const len = buildLabeled(&parts, &buf);
    const salt_slice = if (salt) |s| s else &[_]u8{};
    const prk = HkdfSha512.extract(salt_slice, buf[0..len]);
    @memcpy(out[0..64], &prk);
    out_len.* = 64;
}

fn labeledExpandImpl(
    prk: []const u8,
    info: []const u8,
    label: []const u8,
    suite_id: []const u8,
    out: []u8,
) HpkeError!void {
    const len_part = [_]u8{ @intCast(out.len >> 8), @intCast(out.len & 0xFF) };
    const parts = [_][]const u8{ &len_part, "HPKE-v1", suite_id, label, info };
    if (totalLength(&parts) > 512) {
        return error.InputTooLong;
    }
    var buf: [512]u8 = undefined;
    const len = buildLabeled(&parts, &buf);
    var prk_arr: [64]u8 = undefined;
    @memcpy(&prk_arr, prk[0..64]);
    HkdfSha512.expand(out, buf[0..len], prk_arr);
}

pub const HkdfSha512Vtable = KdfVtable{
    .hash_len = 64,
    .labeledExtract = labeledExtractImpl,
    .labeledExpand = labeledExpandImpl,
};
