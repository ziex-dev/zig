//! HPKE key schedule (RFC 9180 Section 5.1).
//!
//! Derives keys, nonces, and exporter secrets from the shared secret.

const std = @import("std");
const crypto = std.crypto;
const errors = @import("errors.zig");
const kem = @import("kem.zig");
const kdf = @import("kdf.zig");
const aead = @import("aead.zig");

const HpkeError = errors.HpkeError;
const KemId = kem.KemId;
const KdfId = kdf.KdfId;
const AeadId = aead.AeadId;

/// Key material derived by the HPKE key schedule.
///
/// This struct holds the three output secrets from the key schedule:
/// - `key`: the encryption key for the AEAD.
/// - `base_nonce`: the initial nonce used for the AEAD.
/// - `exporter_secret`: the secret used to derive exporter key material.
///
/// The caller is responsible for eventually freeing these buffers with `deinit`.
/// The buffers are allocated during `init` and must be freed with the same
/// allocator passed to `init`.
pub const KeySchedule = struct {
    /// The symmetric encryption key for the AEAD.
    key: []u8,
    /// The base nonce used to compute per-record nonces.
    base_nonce: []u8,
    /// The secret used for exporter key derivation.
    exporter_secret: []u8,

    /// Securely zeroes and frees all allocated memory.
    ///
    /// After this call, the struct is invalidated and should not be used.
    pub fn deinit(self: *KeySchedule, allocator: std.mem.Allocator) void {
        crypto.secureZero(u8, self.key);
        allocator.free(self.key);
        crypto.secureZero(u8, self.base_nonce);
        allocator.free(self.base_nonce);
        crypto.secureZero(u8, self.exporter_secret);
        allocator.free(self.exporter_secret);
        self.* = undefined;
    }

    /// Derives symmetric key material from the shared secret and info.
    ///
    /// This function implements the HPKE key schedule (RFC 9180 Section 5.1).
    ///
    /// Parameters:
    /// - `mode`: the HPKE mode (0x00 Base, 0x01 PSK, 0x02 Auth, 0x03 PSK+Auth).
    /// - `kem_id`: the KEM identifier used in the HPKE suite.
    /// - `kdf_id`: the KDF identifier.
    /// - `aead_id`: the AEAD identifier.
    /// - `shared_secret`: the output of the KEM.
    /// - `info`: application-specific context.
    /// - `psk`: pre-shared key (empty for non-PSK modes).
    /// - `psk_id`: identifier for the PSK (empty for non-PSK modes).
    /// - `kdf_vtable`: the KDF implementation to use.
    /// - `allocator`: memory allocator for the returned buffers.
    ///
    /// Returns a `KeySchedule` containing the derived key, base nonce, and
    /// exporter secret. The caller must call `deinit` to release the memory.
    pub fn init(
        mode: u8,
        kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        shared_secret: []const u8,
        info: []const u8,
        psk: []const u8,
        psk_id: []const u8,
        kdf_vtable: *const kdf.KdfVtable,
        allocator: std.mem.Allocator,
    ) HpkeError!KeySchedule {
        var suite_id_buf: [10]u8 = undefined;
        @memcpy(suite_id_buf[0..4], "HPKE");
        std.mem.writeInt(u16, suite_id_buf[4..6], @intFromEnum(kem_id), .big);
        std.mem.writeInt(u16, suite_id_buf[6..8], @intFromEnum(kdf_id), .big);
        std.mem.writeInt(u16, suite_id_buf[8..10], @intFromEnum(aead_id), .big);
        const suite_id = &suite_id_buf;

        const key_len: usize = switch (aead_id) {
            .aes_128_gcm => aead.Aes128Gcm.key_len,
            .aes_256_gcm => aead.Aes256Gcm.key_len,
            .chacha20_poly1305 => aead.ChaCha20Poly1305.key_len,
        };
        const nonce_len: usize = switch (aead_id) {
            .aes_128_gcm => aead.Aes128Gcm.nonce_len,
            .aes_256_gcm => aead.Aes256Gcm.nonce_len,
            .chacha20_poly1305 => aead.ChaCha20Poly1305.nonce_len,
        };

        // Compute psk_id_hash = LabeledExtract("", "psk_id_hash", psk_id)
        var psk_id_hash_buf: [64]u8 = undefined;
        var psk_id_hash_len: usize = 0;
        try kdf_vtable.labeledExtract(null, psk_id, "psk_id_hash", suite_id, psk_id_hash_buf[0..kdf_vtable.hash_len], &psk_id_hash_len);

        // Compute info_hash = LabeledExtract("", "info_hash", info)
        var info_hash_buf: [64]u8 = undefined;
        var info_hash_len: usize = 0;
        try kdf_vtable.labeledExtract(null, info, "info_hash", suite_id, info_hash_buf[0..kdf_vtable.hash_len], &info_hash_len);

        // key_schedule_context = concat(mode, psk_id_hash, info_hash)
        // Maximum size: 1 + 64 + 64 = 129 bytes.
        var context_buf: [129]u8 = undefined;
        context_buf[0] = mode;
        @memcpy(context_buf[1..][0..psk_id_hash_len], psk_id_hash_buf[0..psk_id_hash_len]);
        @memcpy(context_buf[1 + psk_id_hash_len ..][0..info_hash_len], info_hash_buf[0..info_hash_len]);
        const context = context_buf[0 .. 1 + psk_id_hash_len + info_hash_len];

        // secret = LabeledExtract(shared_secret, "secret", psk)
        var secret_buf: [64]u8 = undefined;
        var secret_len: usize = 0;
        try kdf_vtable.labeledExtract(shared_secret, psk, "secret", suite_id, secret_buf[0..kdf_vtable.hash_len], &secret_len);

        const key = allocator.alloc(u8, key_len) catch return error.AllocationFailed;
        errdefer {
            crypto.secureZero(u8, key);
            allocator.free(key);
        }
        try kdf_vtable.labeledExpand(secret_buf[0..secret_len], context, "key", suite_id, key);

        const base_nonce = allocator.alloc(u8, nonce_len) catch return error.AllocationFailed;
        errdefer {
            crypto.secureZero(u8, base_nonce);
            allocator.free(base_nonce);
        }
        try kdf_vtable.labeledExpand(secret_buf[0..secret_len], context, "base_nonce", suite_id, base_nonce);

        const exp_len = kdf_vtable.hash_len;
        const exporter_secret = allocator.alloc(u8, exp_len) catch return error.AllocationFailed;
        errdefer {
            crypto.secureZero(u8, exporter_secret);
            allocator.free(exporter_secret);
        }
        try kdf_vtable.labeledExpand(secret_buf[0..secret_len], context, "exp", suite_id, exporter_secret);

        return KeySchedule{
            .key = key,
            .base_nonce = base_nonce,
            .exporter_secret = exporter_secret,
        };
    }
};
