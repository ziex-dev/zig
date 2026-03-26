//! KEM identifiers and implementations.
//!
//! This module defines the KEM identifiers (KemId) as specified in RFC 9180,
//! plus additional identifiers for hybrid KEMs from the IETF HPKE Post-Quantum
//! draft.
//!
//! The concrete KEM implementations are exposed under the `dhkem` and top-level
//! namespaces:
//! - `dhkem` contains the DH-based KEMs (X25519, P-256).
//! - `MlKem768X25519`, `MlKem768P256`, `MlKem1024P384` are hybrid KEMs.
//!
//! All KEM types implement the same interface (see `HybridKem` for details).

const std = @import("std");
const crypto = std.crypto;

/// KEM identifiers as per RFC 9180 and the HPKE Post-Quantum draft.
pub const KemId = enum(u16) {
    /// DHKEM with NIST P-256 and HKDF-SHA256.
    dhkem_p256_hkdf_sha256 = 0x0010,
    /// DHKEM with X25519 and HKDF-SHA256.
    dhkem_x25519_hkdf_sha256 = 0x0020,

    // Hybrid KEMs (IETF draft - provisional IDs)
    /// ML-KEM-768 + X25519 hybrid (X-Wing).
    x_wing = 0x647a,
    /// ML-KEM-768 + P-256 hybrid (provisional - not yet assigned).
    ml_kem_768_p256 = 0x11EC,
    /// ML-KEM-1024 + P-384 hybrid (provisional - not yet assigned).
    ml_kem_1024_p384 = 0x11ED,
};

/// Re-export of the DHKEM implementation.
pub const dhkem = @import("dhkem.zig");

// Hybrid KEMs.
const hybrid = @import("hybrid_kem.zig");

/// ML-KEM-768 + X25519 hybrid KEM (X-Wing).
pub const XWing = hybrid.HybridKem(crypto.kem.hybrid.MlKem768X25519, KemId.x_wing);
/// ML-KEM-768 + P-256 hybrid KEM.
pub const MlKem768P256 = hybrid.HybridKem(crypto.kem.hybrid.MlKem768P256, KemId.ml_kem_768_p256);
/// ML-KEM-1024 + P-384 hybrid KEM.
pub const MlKem1024P384 = hybrid.HybridKem(crypto.kem.hybrid.MlKem1024P384, KemId.ml_kem_1024_p384);
