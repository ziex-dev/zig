//! KDF wrappers for HPKE.

const std = @import("std");
const errors = @import("errors.zig");

const HpkeError = errors.HpkeError;

/// KDF identifiers as per RFC 9180.
pub const KdfId = enum(u16) {
    hkdf_sha256 = 0x0001,
    hkdf_sha384 = 0x0002,
    hkdf_sha512 = 0x0003,
};

// Re-export the vtable type and constants.
pub const KdfVtable = @import("kdf/vtable.zig").KdfVtable;
pub const HkdfSha256Vtable = @import("kdf/sha256.zig").HkdfSha256Vtable;
pub const HkdfSha384Vtable = @import("kdf/sha384.zig").HkdfSha384Vtable;
pub const HkdfSha512Vtable = @import("kdf/sha512.zig").HkdfSha512Vtable;

/// Convenience wrapper for labeledExtract with HKDF-SHA256.
///
/// Computes `LabeledExtract(salt, ikm, label, suite_id)`.
///
/// - `salt`: Optional salt (if null, an empty salt is used).
/// - `ikm`: Input keying material.
/// - `label`: Label string.
/// - `suite_id`: Suite identifier byte string.
/// - `out`: Buffer to receive the output (must be at least `hash_len` bytes).
/// - `out_len`: Receives the actual output length (always `hash_len` for SHA-256).
pub fn labeledExtractSha256(
    salt: ?[]const u8,
    ikm: []const u8,
    label: []const u8,
    suite_id: []const u8,
    out: []u8,
    out_len: *usize,
) HpkeError!void {
    return HkdfSha256Vtable.labeledExtract(salt, ikm, label, suite_id, out, out_len);
}

/// Convenience wrapper for labeledExpand with HKDF-SHA256.
///
/// Computes `LabeledExpand(prk, info, label, suite_id, L)` where `L = out.len`.
///
/// - `prk`: Pseudorandom key (output of labeledExtract).
/// - `info`: Context string for expansion.
/// - `label`: Label string.
/// - `suite_id`: Suite identifier byte string.
/// - `out`: Buffer to receive the output.
pub fn labeledExpandSha256(
    prk: []const u8,
    info: []const u8,
    label: []const u8,
    suite_id: []const u8,
    out: []u8,
) HpkeError!void {
    return HkdfSha256Vtable.labeledExpand(prk, info, label, suite_id, out);
}
