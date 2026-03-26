//! HPKE wrapper for hybrid KEMs (ML-KEM + traditional curve).
//!
//! This module provides a generic `HybridKem` that adapts a hybrid KEM type
//! (from `std.crypto.kem.hybrid`) to the HPKE KEM interface defined in RFC 9180.
//!
//! Hybrid KEMs combine a post-quantum KEM (ML-KEM) with a classical Diffie-Hellman
//! curve (X25519, P-256, or P-384) to provide security against both classical and
//! quantum adversaries.
//!
//! Currently supported hybrids:
//! - `MlKem768X25519` (KEM ID `ml_kem_768_x25519`)
//! - `MlKem768P256`   (KEM ID `ml_kem_768_p256`)
//! - `MlKem1024P384`  (KEM ID `ml_kem_1024_p384`)
//!
//! These hybrids follow the IETF hybrid KEM draft specifications. The HPKE wrapper
//! only supports base mode (unauthenticated) because authenticated modes are not
//! yet defined for hybrid KEMs; `authEncap`/`authDecap` return `error.OperationNotSupported`.

const std = @import("std");
const crypto = std.crypto;
const errors = @import("errors.zig");
const kdf = @import("kdf.zig");
const KemId = @import("kem.zig").KemId;

const HpkeError = errors.HpkeError;

/// Creates an HPKE KEM implementation from a hybrid KEM type.
///
/// The returned struct implements the standard HPKE KEM interface with the
/// following fields:
/// - `id`: The KEM identifier (from `KemId`).
/// - `public_key_len`: Length of a public key in bytes.
/// - `private_key_len`: Length of a private key in bytes.
/// - `key_seed_len`: Length of the seed needed to derive a key pair (equal to `private_key_len`).
/// - `encap_seed_len`: Length of the random seed used during encapsulation (varies per hybrid).
/// - `enc_len`: Length of the encapsulated key (ciphertext).
/// - `shared_len`: Length of the shared secret.
/// - `deriveKeyPair(seed)`: Derives a private key from a seed.
/// - `publicFromPrivate(private_key)`: Computes the public key from a private key.
/// - `encaps(peer_public_key, seed)`: Encapsulates a shared secret for the peer.
/// - `decaps(private_key, enc)`: Decapsulates the shared secret.
/// - `authEncap(...)`: Always returns `error.OperationNotSupported`.
/// - `authDecap(...)`: Always returns `error.OperationNotSupported`.
///
/// # Error mapping
/// - `error.NonCanonical` and `error.IdentityElement` from the underlying KEM are
///   mapped to `error.InvalidPeerKey`.
/// - Other encapsulation errors are mapped to `error.EncapsFailed`.
/// - Other decapsulation errors are mapped to `error.DecapsFailed`.
pub fn HybridKem(comptime Hybrid: type, comptime kem_id: KemId) type {
    return struct {
        pub const id = kem_id;
        pub const public_key_len = Hybrid.PublicKey.encoded_length;
        pub const private_key_len = Hybrid.SecretKey.encoded_length;
        pub const key_seed_len = Hybrid.SecretKey.encoded_length;
        pub const encap_seed_len = switch (kem_id) {
            .x_wing => 64, // 32 (ML-KEM seed) + 32 (X25519 seed)
            .ml_kem_768_p256 => 32 + 128, // ML-KEM seed (32) + P-256 seed (128)
            .ml_kem_1024_p384 => 32 + 192, // ML-KEM seed (32) + P-384 seed (192)
            else => @compileError("unknown hybrid KEM id"),
        };
        pub const enc_len = Hybrid.EncapsulatedSecret.ciphertext_length;
        pub const shared_len = Hybrid.EncapsulatedSecret.shared_length;

        /// Derives a private key from a seed.
        ///
        /// For hybrid KEMs, the private key *is* the seed, so this simply returns the seed.
        pub fn deriveKeyPair(seed: [key_seed_len]u8) ![private_key_len]u8 {
            return seed;
        }

        /// Derives the public key from a private key.
        pub fn publicFromPrivate(private_key: [private_key_len]u8) [public_key_len]u8 {
            // Reconstruct the full key pair from the private seed.
            const kp = Hybrid.KeyPair.generateDeterministic(private_key) catch unreachable;
            return kp.public_key.toBytes();
        }

        /// Encapsulates a shared secret for the given peer public key.
        ///
        /// The `seed` must be a cryptographically random byte string of length `encap_seed_len`.
        /// It is used as the randomness for both the classical and post-quantum components.
        pub fn encaps(peer_public_key: [public_key_len]u8, seed: [encap_seed_len]u8) HpkeError!struct { shared_secret: [shared_len]u8, enc: [enc_len]u8 } {
            const pk = Hybrid.PublicKey.fromBytes(&peer_public_key);
            const encap = pk.encapsDeterministic(&seed) catch |err| {
                // Map public key validation errors to InvalidPeerKey.
                if (err == error.NonCanonical or err == error.IdentityElement) {
                    return error.InvalidPeerKey;
                }
                // Any other error indicates a failure during encapsulation.
                return error.EncapsFailed;
            };
            return .{
                .shared_secret = encap.shared_secret,
                .enc = encap.ciphertext,
            };
        }

        /// Decapsulates the shared secret using the private key and the ciphertext.
        pub fn decaps(private_key: [private_key_len]u8, enc: [enc_len]u8) HpkeError![shared_len]u8 {
            const sk = Hybrid.SecretKey.fromBytes(&private_key);
            return sk.decaps(&enc) catch |err| {
                // IdentityElement indicates that the ciphertext is invalid.
                if (err == error.IdentityElement) {
                    return error.InvalidPeerKey;
                }
                // All other errors are mapped to DecapsFailed.
                return error.DecapsFailed;
            };
        }

        /// Authenticated encapsulation is not supported for hybrid KEMs.
        pub fn authEncap(
            _: [private_key_len]u8,
            _: [public_key_len]u8,
            _: [encap_seed_len]u8,
        ) HpkeError!struct { shared_secret: [shared_len]u8, enc: [enc_len]u8 } {
            return error.OperationNotSupported;
        }

        /// Authenticated decapsulation is not supported for hybrid KEMs.
        pub fn authDecap(
            _: [private_key_len]u8,
            _: [enc_len]u8,
            _: [public_key_len]u8,
        ) HpkeError![shared_len]u8 {
            return error.OperationNotSupported;
        }
    };
}
