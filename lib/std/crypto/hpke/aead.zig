//! AEAD identifiers and wrappers for HPKE.

const std = @import("std");
const crypto = std.crypto;
const assert = std.debug.assert;
const HpkeError = @import("errors.zig").HpkeError;

/// AEAD identifiers as per RFC 9180.
pub const AeadId = enum(u16) {
    aes_128_gcm = 0x0001,
    aes_256_gcm = 0x0002,
    chacha20_poly1305 = 0x0003,
};

/// Generic AEAD wrapper.
fn Aead(comptime Impl: type) type {
    return struct {
        pub const key_len = Impl.key_length;
        pub const nonce_len = Impl.nonce_length;
        pub const tag_len = Impl.tag_length;

        pub fn seal(
            key: [key_len]u8,
            nonce: [nonce_len]u8,
            aad: []const u8,
            plaintext: []const u8,
            ciphertext: []u8,
            tag: []u8,
        ) HpkeError!void {
            assert(tag.len >= tag_len);
            const tag_ptr: *[tag_len]u8 = @ptrCast(tag.ptr);
            Impl.encrypt(ciphertext, tag_ptr, plaintext, aad, nonce, key);
        }

        pub fn open(
            key: [key_len]u8,
            nonce: [nonce_len]u8,
            aad: []const u8,
            ciphertext: []const u8,
            tag: []const u8,
            plaintext: []u8,
        ) HpkeError!void {
            assert(tag.len == tag_len);
            var tag_arr: [tag_len]u8 = undefined;
            @memcpy(&tag_arr, tag);
            Impl.decrypt(plaintext, ciphertext, tag_arr, aad, nonce, key) catch return error.DecryptionFailed;
        }
    };
}

pub const Aes128Gcm = Aead(crypto.aead.aes_gcm.Aes128Gcm);
pub const Aes256Gcm = Aead(crypto.aead.aes_gcm.Aes256Gcm);
pub const ChaCha20Poly1305 = Aead(crypto.aead.chacha_poly.ChaCha20Poly1305);
