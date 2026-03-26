//! HPKE context for encrypting/decrypting multiple messages.

const std = @import("std");
const assert = std.debug.assert;
const crypto = std.crypto;
const errors = @import("errors.zig");
const kem = @import("kem.zig");
const kdf = @import("kdf.zig");
const aead = @import("aead.zig");

const HpkeError = errors.HpkeError;
const KemId = kem.KemId;
const KdfId = kdf.KdfId;
const AeadId = aead.AeadId;
const Aes128Gcm = aead.Aes128Gcm;
const Aes256Gcm = aead.Aes256Gcm;
const ChaCha20Poly1305 = aead.ChaCha20Poly1305;

/// HPKE context for a single session.
///
/// A context is created by `setup.Base.sender`/`setup.Base.recipient` or their
/// authenticated/PSK variants. It is used to encrypt or decrypt multiple
/// messages with the same key material.
pub const Context = struct {
    is_sender: bool,
    kem: KemId,
    kdf: KdfId,
    aead: AeadId,
    key: []u8,
    base_nonce: [12]u8,
    exporter_secret: []u8,
    seq: u64,
    tag_len: usize,
    nonce_len: usize,
    key_len: usize,
    kdf_vtable: *const kdf.KdfVtable,

    const Self = @This();

    /// Initialises a context with the given parameters.
    ///
    /// This function is called internally by the setup functions.
    pub fn init(
        is_sender: bool,
        kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        key: []u8,
        base_nonce: []u8,
        exporter_secret: []u8,
        kdf_vtable: *const kdf.KdfVtable,
    ) Self {
        const tag_len: usize = switch (aead_id) {
            .aes_128_gcm => Aes128Gcm.tag_len,
            .aes_256_gcm => Aes256Gcm.tag_len,
            .chacha20_poly1305 => ChaCha20Poly1305.tag_len,
        };
        const nonce_len: usize = switch (aead_id) {
            .aes_128_gcm => Aes128Gcm.nonce_len,
            .aes_256_gcm => Aes256Gcm.nonce_len,
            .chacha20_poly1305 => ChaCha20Poly1305.nonce_len,
        };
        const key_len: usize = switch (aead_id) {
            .aes_128_gcm => Aes128Gcm.key_len,
            .aes_256_gcm => Aes256Gcm.key_len,
            .chacha20_poly1305 => ChaCha20Poly1305.key_len,
        };
        var bn: [12]u8 = undefined;
        @memcpy(&bn, base_nonce);
        return .{
            .is_sender = is_sender,
            .kem = kem_id,
            .kdf = kdf_id,
            .aead = aead_id,
            .key = key,
            .base_nonce = bn,
            .exporter_secret = exporter_secret,
            .seq = 0,
            .tag_len = tag_len,
            .nonce_len = nonce_len,
            .key_len = key_len,
            .kdf_vtable = kdf_vtable,
        };
    }

    /// Frees the internal buffers and securely zeros them before deallocation.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        crypto.secureZero(u8, self.key);
        allocator.free(self.key);
        crypto.secureZero(u8, self.exporter_secret);
        allocator.free(self.exporter_secret);
        self.* = undefined;
    }

    fn buildSuiteId(self: Self, out: []u8) HpkeError!usize {
        if (out.len < 10) return error.InvalidContext;
        @memcpy(out[0..4], "HPKE");
        std.mem.writeInt(u16, out[4..6], @intFromEnum(self.kem), .big);
        std.mem.writeInt(u16, out[6..8], @intFromEnum(self.kdf), .big);
        std.mem.writeInt(u16, out[8..10], @intFromEnum(self.aead), .big);
        return 10;
    }

    fn computeNonce(self: Self, out: []u8) void {
        const nonce_len = self.nonce_len;
        assert(out.len >= nonce_len);
        @memcpy(out[0..nonce_len], self.base_nonce[0..nonce_len]);
        const seq = self.seq;
        for (0..8) |i| {
            const shift = @as(u6, @intCast(56 - 8 * i));
            const byte = @as(u8, @truncate(seq >> shift));
            out[nonce_len - 8 + i] ^= byte;
        }
    }

    fn sealInternal(self: *Self, out: []u8, in_: []const u8, aad: []const u8) HpkeError!usize {
        if (!self.is_sender) return error.InvalidContext;
        if (self.seq == std.math.maxInt(u64)) return error.SequenceOverflow;

        var nonce: [12]u8 = undefined;
        self.computeNonce(nonce[0..self.nonce_len]);

        const tag_len = self.tag_len;
        const ciphertext_len = in_.len;
        const total_out_len = ciphertext_len + tag_len;
        if (out.len < total_out_len) return error.InvalidContext;

        const tag_out = out[ciphertext_len..][0..tag_len];
        const ciphertext_out = out[0..ciphertext_len];
        switch (self.aead) {
            .aes_128_gcm => {
                var key: [Aes128Gcm.key_len]u8 = undefined;
                @memcpy(&key, self.key[0..self.key_len]);
                try Aes128Gcm.seal(key, nonce[0..12].*, aad, in_, ciphertext_out, tag_out);
            },
            .aes_256_gcm => {
                var key: [Aes256Gcm.key_len]u8 = undefined;
                @memcpy(&key, self.key[0..self.key_len]);
                try Aes256Gcm.seal(key, nonce[0..12].*, aad, in_, ciphertext_out, tag_out);
            },
            .chacha20_poly1305 => {
                var key: [ChaCha20Poly1305.key_len]u8 = undefined;
                @memcpy(&key, self.key[0..self.key_len]);
                try ChaCha20Poly1305.seal(key, nonce[0..12].*, aad, in_, ciphertext_out, tag_out);
            },
        }

        self.seq +%= 1;
        return total_out_len;
    }

    fn openInternal(self: *Self, out: []u8, in_: []const u8, aad: []const u8) HpkeError!usize {
        if (self.is_sender) return error.InvalidContext;
        if (self.seq == std.math.maxInt(u64)) return error.SequenceOverflow;

        var nonce: [12]u8 = undefined;
        self.computeNonce(nonce[0..self.nonce_len]);

        const tag_len = self.tag_len;
        if (in_.len < tag_len) return error.DecryptionFailed;
        const ciphertext_len = in_.len - tag_len;
        const ciphertext = in_[0..ciphertext_len];
        const tag = in_[ciphertext_len..];

        if (out.len < ciphertext_len) return error.InvalidContext;

        switch (self.aead) {
            .aes_128_gcm => {
                var key: [Aes128Gcm.key_len]u8 = undefined;
                @memcpy(&key, self.key[0..self.key_len]);
                try Aes128Gcm.open(key, nonce[0..12].*, aad, ciphertext, tag, out[0..ciphertext_len]);
            },
            .aes_256_gcm => {
                var key: [Aes256Gcm.key_len]u8 = undefined;
                @memcpy(&key, self.key[0..self.key_len]);
                try Aes256Gcm.open(key, nonce[0..12].*, aad, ciphertext, tag, out[0..ciphertext_len]);
            },
            .chacha20_poly1305 => {
                var key: [ChaCha20Poly1305.key_len]u8 = undefined;
                @memcpy(&key, self.key[0..self.key_len]);
                try ChaCha20Poly1305.open(key, nonce[0..12].*, aad, ciphertext, tag, out[0..ciphertext_len]);
            },
        }

        self.seq +%= 1;
        return ciphertext_len;
    }

    /// Encrypts a message and returns the ciphertext (including the authentication tag).
    ///
    /// - `allocator`: Used to allocate the returned slice.
    /// - `plaintext`: Message to encrypt.
    /// - `aad`: Additional authenticated data.
    ///
    /// Returns a newly allocated slice containing the ciphertext followed by the tag.
    /// The caller is responsible for freeing it.
    pub fn seal(self: *Self, allocator: std.mem.Allocator, plaintext: []const u8, aad: []const u8) ![]u8 {
        const overhead = self.tag_len;
        const out = try allocator.alloc(u8, plaintext.len + overhead);
        errdefer allocator.free(out);
        const written = try self.sealInternal(out, plaintext, aad);
        assert(written == out.len);
        return out;
    }

    /// Decrypts a ciphertext and returns the plaintext.
    ///
    /// - `allocator`: Used to allocate the returned slice.
    /// - `ciphertext`: The ciphertext (including the tag).
    /// - `aad`: Additional authenticated data.
    ///
    /// Returns a newly allocated slice containing the plaintext.
    /// The caller is responsible for freeing it.
    ///
    /// May return `error.DecryptionFailed` if the tag does not verify.
    pub fn open(self: *Self, allocator: std.mem.Allocator, ciphertext: []const u8, aad: []const u8) ![]u8 {
        const overhead = self.tag_len;
        if (ciphertext.len < overhead) return error.DecryptionFailed;
        const out = try allocator.alloc(u8, ciphertext.len - overhead);
        errdefer allocator.free(out);
        const written = try self.openInternal(out, ciphertext, aad);
        assert(written == out.len);
        return out;
    }

    /// Derives additional key material from the context.
    ///
    /// - `allocator`: Used to allocate the returned slice.
    /// - `context`: Context string for the exporter.
    /// - `len`: Desired length of the output.
    ///
    /// Returns a newly allocated slice of length `len` containing the exporter output.
    /// The caller is responsible for freeing it.
    pub fn exportSecret(self: *Self, allocator: std.mem.Allocator, context: []const u8, len: usize) ![]u8 {
        const out = try allocator.alloc(u8, len);
        errdefer allocator.free(out);

        var suite_id_buf: [10]u8 = undefined;
        const suite_id_len = try self.buildSuiteId(&suite_id_buf);
        const suite_id = suite_id_buf[0..suite_id_len];

        try self.kdf_vtable.labeledExpand(self.exporter_secret, context, "sec", suite_id, out);
        return out;
    }
};
