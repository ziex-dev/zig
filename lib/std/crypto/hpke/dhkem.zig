//! Generic DHKEM implementation for HPKE.

const std = @import("std");
const crypto = std.crypto;
const errors = @import("errors.zig");
const kdf = @import("kdf.zig");
const KemId = @import("kem.zig").KemId;

// Supported DH Groups
const P256Group = @import("dhgroup/p256.zig").P256Group;
const X25519Group = @import("dhgroup/x25519.zig").X25519Group;

const P256Ecc = crypto.ecc.P256; // for scalar validation

// Public DHKEM API

/// DHKEM using the NIST P-256 curve and HKDF-SHA256.
pub const P256 = struct {
    /// HKDF-SHA256 variant.
    pub const hkdf = struct {
        /// The actual KEM implementation.
        pub const sha256 = DhKemFn(P256Group, .hkdf_sha256, KemId.dhkem_p256_hkdf_sha256);
    };
};

/// DHKEM using the X25519 curve and HKDF-SHA256.
pub const X25519 = struct {
    /// HKDF-SHA256 variant.
    pub const hkdf = struct {
        /// The actual KEM implementation.
        pub const sha256 = DhKemFn(X25519Group, .hkdf_sha256, KemId.dhkem_x25519_hkdf_sha256);
    };
};

// Internal generic DHKEM implementation
// Note: Currently only supporting HKDF SHA256
// DHKEM is only defined with HKDF-SHA256 in the standard.
// The _kdf_id parameter is present only for API compatibility with
// the HPKE setup functions; it is ignored.
fn DhKemFn(comptime Group: type, comptime _kdf_id: kdf.KdfId, comptime kem_id: KemId) type {
    _ = _kdf_id;
    return struct {
        pub const id = kem_id;
        pub const public_key_len = Group.public_key_len;
        pub const private_key_len = Group.private_key_len;
        pub const seed_len = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => 32,
            .dhkem_p256_hkdf_sha256 => 32,
            else => unreachable, // only DHKEMs are used with this function
        };
        pub const encap_seed_len = seed_len; // same as seed_len for DHKEMs
        pub const enc_len = public_key_len;
        pub const shared_len = Group.shared_len;

        fn derivePrivateKey(seed: [seed_len]u8) ![private_key_len]u8 {
            if (kem_id == .dhkem_x25519_hkdf_sha256) return seed;
            var suite_id: [5]u8 = undefined;
            @memcpy(suite_id[0..3], "KEM");
            std.mem.writeInt(u16, suite_id[3..5], @intFromEnum(kem_id), .big);

            var dkp_prk: [32]u8 = undefined;
            var dkp_prk_len: usize = 0;
            try kdf.labeledExtractSha256(null, &seed, "dkp_prk", &suite_id, &dkp_prk, &dkp_prk_len);

            var candidate: [private_key_len]u8 = undefined;
            for (0..255) |counter| {
                var counter_bytes: [1]u8 = undefined;
                counter_bytes[0] = @intCast(counter & 0xff);
                try kdf.labeledExpandSha256(&dkp_prk, &counter_bytes, "candidate", &suite_id, &candidate);
                // Validate candidate scalar (non-zero and < order). Probability of failure is negligible.
                const scalar = P256Ecc.scalar.Scalar.fromBytes(candidate, .big) catch continue;
                if (scalar.isZero()) continue;
                return candidate;
            }
            return error.DeriveKeyFailed;
        }

        /// Derives a private key from a seed.
        pub fn deriveKeyPair(seed: [seed_len]u8) ![private_key_len]u8 {
            return try derivePrivateKey(seed);
        }

        /// Computes the public key from a private key.
        pub fn publicFromPrivate(private_key: [private_key_len]u8) [public_key_len]u8 {
            return Group.publicFromPrivate(private_key);
        }

        /// Encapsulates a shared secret for the given peer public key.
        ///
        /// - `peer_public_key`: Recipient's public key.
        /// - `seed`: Random seed for ephemeral key generation.
        ///
        /// Returns the shared secret and the encapsulated key (`enc`).
        pub fn encaps(peer_public_key: [public_key_len]u8, seed: [encap_seed_len]u8) !struct { shared_secret: [32]u8, enc: [enc_len]u8 } {
            // Extract the first seed_len bytes for the private key.
            var private_key_arr: [seed_len]u8 = undefined;
            @memcpy(&private_key_arr, seed[0..seed_len]);
            const private_key = try derivePrivateKey(private_key_arr);
            const enc = publicFromPrivate(private_key);
            const dh = Group.dh(private_key, peer_public_key) catch return error.InvalidPeerKey;

            var kem_context: [2 * public_key_len]u8 = undefined;
            @memcpy(kem_context[0..public_key_len], &enc);
            @memcpy(kem_context[public_key_len..], &peer_public_key);

            var suite_id: [5]u8 = undefined;
            @memcpy(suite_id[0..3], "KEM");
            std.mem.writeInt(u16, suite_id[3..5], @intFromEnum(kem_id), .big);

            var prk: [32]u8 = undefined;
            var prk_len: usize = 0;
            try kdf.labeledExtractSha256(null, &dh, "eae_prk", &suite_id, &prk, &prk_len);
            var shared_secret: [32]u8 = undefined;
            try kdf.labeledExpandSha256(&prk, &kem_context, "shared_secret", &suite_id, &shared_secret);

            return .{ .shared_secret = shared_secret, .enc = enc };
        }

        /// Decapsulates a shared secret using the private key and the encapsulated key.
        ///
        /// - `private_key`: Recipient's private key.
        /// - `enc`: Encapsulated key (ciphertext).
        pub fn decaps(private_key: [private_key_len]u8, enc: [enc_len]u8) ![32]u8 {
            const dh = Group.dh(private_key, enc) catch return error.InvalidPeerKey;
            const public_key = publicFromPrivate(private_key);

            var kem_context: [2 * public_key_len]u8 = undefined;
            @memcpy(kem_context[0..public_key_len], &enc);
            @memcpy(kem_context[public_key_len..], &public_key);

            var suite_id: [5]u8 = undefined;
            @memcpy(suite_id[0..3], "KEM");
            std.mem.writeInt(u16, suite_id[3..5], @intFromEnum(kem_id), .big);

            var prk: [32]u8 = undefined;
            var prk_len: usize = 0;
            try kdf.labeledExtractSha256(null, &dh, "eae_prk", &suite_id, &prk, &prk_len);
            var shared_secret: [32]u8 = undefined;
            try kdf.labeledExpandSha256(&prk, &kem_context, "shared_secret", &suite_id, &shared_secret);

            return shared_secret;
        }

        /// Authenticated encapsulation: the sender authenticates with a static private key.
        pub fn authEncap(
            sender_static_private: [private_key_len]u8,
            peer_public_key: [public_key_len]u8,
            seed: [encap_seed_len]u8,
        ) !struct { shared_secret: [32]u8, enc: [enc_len]u8 } {
            // Extract the first seed_len bytes for the ephemeral private key.
            var ephemeral_private_arr: [seed_len]u8 = undefined;
            @memcpy(&ephemeral_private_arr, seed[0..seed_len]);
            const ephemeral_private = try derivePrivateKey(ephemeral_private_arr);
            const enc = publicFromPrivate(ephemeral_private);
            const dh1 = Group.dh(ephemeral_private, peer_public_key) catch return error.InvalidPeerKey;
            const dh2 = Group.dh(sender_static_private, peer_public_key) catch return error.InvalidPeerKey;

            var dh_combined: [2 * shared_len]u8 = undefined;
            @memcpy(dh_combined[0..shared_len], &dh1);
            @memcpy(dh_combined[shared_len..], &dh2);

            const sender_static_public = publicFromPrivate(sender_static_private);
            var kem_context: [3 * public_key_len]u8 = undefined;
            @memcpy(kem_context[0..public_key_len], &enc);
            @memcpy(kem_context[public_key_len..][0..public_key_len], &peer_public_key);
            @memcpy(kem_context[2 * public_key_len ..][0..public_key_len], &sender_static_public);

            var suite_id: [5]u8 = undefined;
            @memcpy(suite_id[0..3], "KEM");
            std.mem.writeInt(u16, suite_id[3..5], @intFromEnum(kem_id), .big);

            var prk: [32]u8 = undefined;
            var prk_len: usize = 0;
            try kdf.labeledExtractSha256(null, &dh_combined, "eae_prk", &suite_id, &prk, &prk_len);
            var shared_secret: [32]u8 = undefined;
            try kdf.labeledExpandSha256(&prk, &kem_context, "shared_secret", &suite_id, &shared_secret);

            return .{ .shared_secret = shared_secret, .enc = enc };
        }

        /// Authenticated decapsulation: the recipient verifies the sender's public key.
        pub fn authDecap(
            private_key: [private_key_len]u8,
            enc: [enc_len]u8,
            sender_public_key: [public_key_len]u8,
        ) ![32]u8 {
            const dh1 = Group.dh(private_key, enc) catch return error.InvalidPeerKey;
            const dh2 = Group.dh(private_key, sender_public_key) catch return error.InvalidPeerKey;

            var dh_combined: [2 * shared_len]u8 = undefined;
            @memcpy(dh_combined[0..shared_len], &dh1);
            @memcpy(dh_combined[shared_len..], &dh2);

            const public_key = publicFromPrivate(private_key);
            var kem_context: [3 * public_key_len]u8 = undefined;
            @memcpy(kem_context[0..public_key_len], &enc);
            @memcpy(kem_context[public_key_len..][0..public_key_len], &public_key);
            @memcpy(kem_context[2 * public_key_len ..][0..public_key_len], &sender_public_key);

            var suite_id: [5]u8 = undefined;
            @memcpy(suite_id[0..3], "KEM");
            std.mem.writeInt(u16, suite_id[3..5], @intFromEnum(kem_id), .big);

            var prk: [32]u8 = undefined;
            var prk_len: usize = 0;
            try kdf.labeledExtractSha256(null, &dh_combined, "eae_prk", &suite_id, &prk, &prk_len);
            var shared_secret: [32]u8 = undefined;
            try kdf.labeledExpandSha256(&prk, &kem_context, "shared_secret", &suite_id, &shared_secret);

            return shared_secret;
        }
    };
}
