//! HPKE (RFC 9180) implementation for Zig.
//!
//! This module provides a pure-Zig implementation of Hybrid Public Key Encryption.
//! It supports the mandatory suite (DHKEM_X25519_HKDF_SHA256 + HKDF_SHA256 + AES_128_GCM)
//! and is easily extensible to other algorithms.
//!
//! # Modes
//! - **Base mode** (unauthenticated): `setup.Base.sender`, `setup.Base.recipient`
//! - **PSK mode** (pre-shared key): `setup.Psk.sender`, `setup.Psk.recipient`
//! - **Auth mode** (sender authentication): `setup.Auth.sender`, `setup.Auth.recipient`
//! - **PSK+Auth mode** (combined): `setup.PskAuth.sender`, `setup.PskAuth.recipient`
//!
//! # Example
//! ```
//! const std = @import("std");
//! const crypto = std.crypto;
//! const hpke = @import("hpke");
//!
//! pub fn main(init: std.process.Init) !void {
//!     const allocator = init.gpa;
//!     const io = init.io;
//!
//!     const recipient_kp = crypto.dh.X25519.KeyPair.generate(io);
//!     var sender = try hpke.setup.Base.sender(
//!         .dhkem_x25519_hkdf_sha256,
//!         .hkdf_sha256,
//!         .aes_128_gcm,
//!         &recipient_kp.public_key,
//!         "info",
//!         io,
//!         allocator,
//!     );
//!     defer {
//!         allocator.free(sender.enc);
//!         sender.ctx.deinit(allocator);
//!     }
//!
//!     const ciphertext = try sender.ctx.seal(allocator, "Hello, world!", "");
//!     defer allocator.free(ciphertext);
//!
//!     // ... send `sender.enc` and `ciphertext` to recipient ...
//! }
//! ```

const std = @import("std");
const crypto = std.crypto;
const hkdf = crypto.kdf.hkdf;

// -----------------------------------------------------------------------------
// Re-exported modules
// -----------------------------------------------------------------------------
const errors = @import("errors.zig");
const kdf = @import("kdf.zig");
const aead = @import("aead.zig");
const schedule = @import("schedule.zig");

pub const setup = @import("setup.zig");
pub const kem = @import("kem.zig");

pub const HpkeError = errors.HpkeError;
pub const KemId = kem.KemId;
pub const KdfId = kdf.KdfId;
pub const AeadId = aead.AeadId;
