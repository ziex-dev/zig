//! HPKE setup functions (Base, Auth, PSK, and PSK+Auth modes).
//!
//! This module provides the entry points for setting up a sender or recipient
//! context in base, authenticated, or PSK mode.
//!
//! # Modes
//! - **Base mode** (unauthenticated): `BaseMode.sender` / `BaseMode.recipient`
//! - **PSK mode** (pre-shared key): `PSKMode.sender` / `PSKMode.recipient`
//! - **Auth mode** (sender authentication): `AuthMode.sender` / `AuthMode.recipient`
//! - **PSK+Auth mode** (combined): `PSKAuthMode.sender` / `PSKAuthMode.recipient`
//!
//! All setup functions return a `Sender` or `Recipient` struct that wraps a `Context`
//! and (for senders) the encapsulated key `enc`. Call `deinit` on the returned object
//! to securely zero and free all allocated resources.

const std = @import("std");
const crypto = std.crypto;
const errors = @import("errors.zig");
const kem = @import("kem.zig");
const kdf = @import("kdf.zig");
const aead = @import("aead.zig");
const schedule = @import("schedule.zig");
const context = @import("context.zig");

const HpkeError = errors.HpkeError;
const Context = context.Context;
const KemId = kem.KemId;
const KdfId = kdf.KdfId;
const AeadId = aead.AeadId;

// -----------------------------------------------------------------------------
// Internal helpers
// -----------------------------------------------------------------------------

/// Internal helper to create a sender context.
fn createSender(
    comptime mode: u8,
    comptime use_auth: bool,
    comptime use_psk: bool,
    comptime kem_id: KemId,
    kdf_id: KdfId,
    aead_id: AeadId,
    peer_public_key: []const u8,
    info: []const u8,
    maybe_sender_private: ?[]const u8,
    psk: []const u8,
    psk_id: []const u8,
    io: std.Io,
    allocator: std.mem.Allocator,
) HpkeError!struct { ctx: Context, enc: []u8 } {
    const kem_impl = switch (kem_id) {
        .dhkem_p256_hkdf_sha256 => kem.dhkem.P256.hkdf.sha256,
        .dhkem_x25519_hkdf_sha256 => kem.dhkem.X25519.hkdf.sha256,
        .x_wing => kem.XWing,
        .ml_kem_768_p256 => kem.MlKem768P256,
        .ml_kem_1024_p384 => kem.MlKem1024P384,
    };
    if (peer_public_key.len != kem_impl.public_key_len) return error.InvalidKeyLength;

    var seed: [kem_impl.encap_seed_len]u8 = undefined;
    io.random(&seed);
    const encap = if (use_auth) blk: {
        const sender_private = maybe_sender_private orelse return error.InvalidKeyLength;
        if (sender_private.len != kem_impl.private_key_len) return error.InvalidKeyLength;
        break :blk try kem_impl.authEncap(sender_private[0..kem_impl.private_key_len].*, peer_public_key[0..kem_impl.public_key_len].*, seed);
    } else blk: {
        break :blk try kem_impl.encaps(peer_public_key[0..kem_impl.public_key_len].*, seed);
    };
    const enc = allocator.dupe(u8, &encap.enc) catch return error.AllocationFailed;
    errdefer allocator.free(enc);

    const kdf_vtable = switch (kdf_id) {
        .hkdf_sha256 => &kdf.HkdfSha256Vtable,
        .hkdf_sha384 => &kdf.HkdfSha384Vtable,
        .hkdf_sha512 => &kdf.HkdfSha512Vtable,
    };
    const key_material = try schedule.KeySchedule.init(
        mode,
        kem_id,
        kdf_id,
        aead_id,
        &encap.shared_secret,
        info,
        if (use_psk) psk else &[_]u8{},
        if (use_psk) psk_id else &[_]u8{},
        kdf_vtable,
        allocator,
    );
    const ctx = Context.init(true, kem_id, kdf_id, aead_id, key_material.key, key_material.base_nonce, key_material.exporter_secret, kdf_vtable);
    // After transferring ownership of key and exporter_secret to the context,
    // and copying base_nonce, we free the base_nonce slice.
    // KeySchedule.deinit is not called because key and exporter_secret must stay alive.
    crypto.secureZero(u8, key_material.base_nonce);
    allocator.free(key_material.base_nonce);
    return .{ .ctx = ctx, .enc = enc };
}

/// Internal helper to create a recipient context.
fn createRecipient(
    comptime mode: u8,
    comptime use_auth: bool,
    comptime use_psk: bool,
    comptime kem_id: KemId,
    kdf_id: KdfId,
    aead_id: AeadId,
    private_key: []const u8,
    maybe_sender_public: ?[]const u8,
    enc: []const u8,
    info: []const u8,
    psk: []const u8,
    psk_id: []const u8,
    allocator: std.mem.Allocator,
) HpkeError!Context {
    const kem_impl = switch (kem_id) {
        .dhkem_p256_hkdf_sha256 => kem.dhkem.P256.hkdf.sha256,
        .dhkem_x25519_hkdf_sha256 => kem.dhkem.X25519.hkdf.sha256,
        .x_wing => kem.XWing,
        .ml_kem_768_p256 => kem.MlKem768P256,
        .ml_kem_1024_p384 => kem.MlKem1024P384,
    };
    if (private_key.len != kem_impl.private_key_len) return error.InvalidKeyLength;
    if (enc.len != kem_impl.enc_len) return error.InvalidKeyLength;

    const shared_secret = if (use_auth) blk: {
        const sender_public = maybe_sender_public orelse return error.InvalidKeyLength;
        if (sender_public.len != kem_impl.public_key_len) return error.InvalidKeyLength;
        break :blk try kem_impl.authDecap(
            private_key[0..kem_impl.private_key_len].*,
            enc[0..kem_impl.enc_len].*,
            sender_public[0..kem_impl.public_key_len].*,
        );
    } else blk: {
        break :blk try kem_impl.decaps(private_key[0..kem_impl.private_key_len].*, enc[0..kem_impl.enc_len].*);
    };
    const kdf_vtable = switch (kdf_id) {
        .hkdf_sha256 => &kdf.HkdfSha256Vtable,
        .hkdf_sha384 => &kdf.HkdfSha384Vtable,
        .hkdf_sha512 => &kdf.HkdfSha512Vtable,
    };
    const key_material = try schedule.KeySchedule.init(
        mode,
        kem_id,
        kdf_id,
        aead_id,
        &shared_secret,
        info,
        if (use_psk) psk else &[_]u8{},
        if (use_psk) psk_id else &[_]u8{},
        kdf_vtable,
        allocator,
    );
    const ctx = Context.init(false, kem_id, kdf_id, aead_id, key_material.key, key_material.base_nonce, key_material.exporter_secret, kdf_vtable);
    // After transferring ownership of key and exporter_secret to the context,
    // and copying base_nonce, we free the base_nonce slice.
    // KeySchedule.deinit is not called because key and exporter_secret must stay alive.
    crypto.secureZero(u8, key_material.base_nonce);
    allocator.free(key_material.base_nonce);
    return ctx;
}

// -----------------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------------

/// Base mode (unauthenticated) - no sender authentication.
pub const BaseMode = struct {
    /// Sender context for base mode.
    ///
    /// The sender generates an ephemeral key pair, encapsulates the shared secret,
    /// and derives the symmetric key material. The returned `Sender` contains the
    /// context for encrypting messages and the encapsulated key `enc` that must be
    /// sent to the recipient.
    pub const Sender = struct {
        context: Context,
        enc: []u8,

        /// Securely zeroes and frees the encapsulated key and the internal context.
        pub fn deinit(self: *Sender, allocator: std.mem.Allocator) void {
            allocator.free(self.enc);
            self.context.deinit(allocator);
            self.* = undefined;
        }
    };

    /// Recipient context for base mode.
    ///
    /// The recipient uses its static private key and the received `enc` to derive
    /// the symmetric key material. The returned `Recipient` contains the context
    /// for decrypting messages.
    pub const Recipient = struct {
        context: Context,

        /// Securely zeroes and frees the internal context.
        pub fn deinit(self: *Recipient, allocator: std.mem.Allocator) void {
            self.context.deinit(allocator);
            self.* = undefined;
        }
    };

    /// Creates a sender context in base mode.
    ///
    /// - `kem_id`: The KEM to use (must be a DHKEM or hybrid KEM).
    /// - `kdf_id`: The KDF to use.
    /// - `aead_id`: The AEAD to use.
    /// - `peer_public_key`: The recipient's public key.
    /// - `info`: Application-specific info string.
    /// - `io`: I/O backend for random bytes.
    /// - `allocator`: Memory allocator for the returned buffers.
    ///
    /// Returns a `Sender` containing the context and the encapsulated key.
    pub fn sender(
        comptime kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        peer_public_key: []const u8,
        info: []const u8,
        io: std.Io,
        allocator: std.mem.Allocator,
    ) HpkeError!Sender {
        const result = try createSender(
            0x00,
            false,
            false,
            kem_id,
            kdf_id,
            aead_id,
            peer_public_key,
            info,
            null,
            &[_]u8{},
            &[_]u8{},
            io,
            allocator,
        );
        return .{ .context = result.ctx, .enc = result.enc };
    }

    /// Creates a recipient context in base mode.
    ///
    /// - `kem_id`: The KEM to use (must be a DHKEM or hybrid KEM).
    /// - `kdf_id`: The KDF to use.
    /// - `aead_id`: The AEAD to use.
    /// - `private_key`: The recipient's static private key.
    /// - `enc`: The encapsulated key received from the sender.
    /// - `info`: Application-specific info string (must match the sender's).
    /// - `allocator`: Memory allocator for the returned buffers.
    ///
    /// Returns a `Recipient` containing the context for decryption.
    pub fn recipient(
        comptime kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        private_key: []const u8,
        enc: []const u8,
        info: []const u8,
        allocator: std.mem.Allocator,
    ) HpkeError!Recipient {
        const ctx = try createRecipient(
            0x00,
            false,
            false,
            kem_id,
            kdf_id,
            aead_id,
            private_key,
            null,
            enc,
            info,
            &[_]u8{},
            &[_]u8{},
            allocator,
        );
        return .{ .context = ctx };
    }
};

/// PSK mode (pre-shared key) - both parties share a secret.
pub const PSKMode = struct {
    pub const Sender = struct {
        context: Context,
        enc: []u8,

        pub fn deinit(self: *Sender, allocator: std.mem.Allocator) void {
            allocator.free(self.enc);
            self.context.deinit(allocator);
            self.* = undefined;
        }
    };

    pub const Recipient = struct {
        context: Context,

        pub fn deinit(self: *Recipient, allocator: std.mem.Allocator) void {
            self.context.deinit(allocator);
            self.* = undefined;
        }
    };

    /// Creates a sender context in PSK mode.
    ///
    /// - `kem_id`: The KEM to use (must be a DHKEM or hybrid KEM).
    /// - `kdf_id`: The KDF to use.
    /// - `aead_id`: The AEAD to use.
    /// - `peer_public_key`: The recipient's public key.
    /// - `info`: Application-specific info string.
    /// - `psk`: Pre-shared key material.
    /// - `psk_id`: Identifier for the PSK (may be empty).
    /// - `io`: I/O backend for random bytes.
    /// - `allocator`: Memory allocator for the returned buffers.
    ///
    /// Returns a `Sender` containing the context and the encapsulated key.
    pub fn sender(
        comptime kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        peer_public_key: []const u8,
        info: []const u8,
        psk: []const u8,
        psk_id: []const u8,
        io: std.Io,
        allocator: std.mem.Allocator,
    ) HpkeError!Sender {
        const result = try createSender(
            0x01,
            false,
            true,
            kem_id,
            kdf_id,
            aead_id,
            peer_public_key,
            info,
            null,
            psk,
            psk_id,
            io,
            allocator,
        );
        return .{ .context = result.ctx, .enc = result.enc };
    }

    /// Creates a recipient context in PSK mode.
    ///
    /// - `kem_id`: The KEM to use (must be a DHKEM or hybrid KEM).
    /// - `kdf_id`: The KDF to use.
    /// - `aead_id`: The AEAD to use.
    /// - `private_key`: The recipient's static private key.
    /// - `enc`: The encapsulated key received from the sender.
    /// - `info`: Application-specific info string.
    /// - `psk`: Pre-shared key material (must match the sender's).
    /// - `psk_id`: Identifier for the PSK (must match the sender's).
    /// - `allocator`: Memory allocator for the returned buffers.
    ///
    /// Returns a `Recipient` containing the context for decryption.
    pub fn recipient(
        comptime kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        private_key: []const u8,
        enc: []const u8,
        info: []const u8,
        psk: []const u8,
        psk_id: []const u8,
        allocator: std.mem.Allocator,
    ) HpkeError!Recipient {
        const ctx = try createRecipient(
            0x01,
            false,
            true,
            kem_id,
            kdf_id,
            aead_id,
            private_key,
            null,
            enc,
            info,
            psk,
            psk_id,
            allocator,
        );
        return .{ .context = ctx };
    }
};

/// Auth mode (sender authentication) - the sender authenticates with a static key.
pub const AuthMode = struct {
    pub const Sender = struct {
        context: Context,
        enc: []u8,

        pub fn deinit(self: *Sender, allocator: std.mem.Allocator) void {
            allocator.free(self.enc);
            self.context.deinit(allocator);
            self.* = undefined;
        }
    };

    pub const Recipient = struct {
        context: Context,

        pub fn deinit(self: *Recipient, allocator: std.mem.Allocator) void {
            self.context.deinit(allocator);
            self.* = undefined;
        }
    };

    /// Creates a sender context in Auth mode.
    ///
    /// - `kem_id`: The KEM to use (must be a DHKEM; hybrid KEMs do not support auth).
    /// - `kdf_id`: The KDF to use.
    /// - `aead_id`: The AEAD to use.
    /// - `sender_private_key`: The sender's static private key.
    /// - `peer_public_key`: The recipient's public key.
    /// - `info`: Application-specific info string.
    /// - `io`: I/O backend for random bytes.
    /// - `allocator`: Memory allocator for the returned buffers.
    ///
    /// Returns a `Sender` containing the context and the encapsulated key.
    pub fn sender(
        comptime kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        sender_private_key: []const u8,
        peer_public_key: []const u8,
        info: []const u8,
        io: std.Io,
        allocator: std.mem.Allocator,
    ) HpkeError!Sender {
        const result = try createSender(
            0x02,
            true,
            false,
            kem_id,
            kdf_id,
            aead_id,
            peer_public_key,
            info,
            sender_private_key,
            &[_]u8{},
            &[_]u8{},
            io,
            allocator,
        );
        return .{ .context = result.ctx, .enc = result.enc };
    }

    /// Creates a recipient context in Auth mode.
    ///
    /// - `kem_id`: The KEM to use (must be a DHKEM; hybrid KEMs do not support auth).
    /// - `kdf_id`: The KDF to use.
    /// - `aead_id`: The AEAD to use.
    /// - `recipient_private_key`: The recipient's static private key.
    /// - `sender_public_key`: The sender's public key.
    /// - `enc`: The encapsulated key received from the sender.
    /// - `info`: Application-specific info string.
    /// - `allocator`: Memory allocator for the returned buffers.
    ///
    /// Returns a `Recipient` containing the context for decryption.
    pub fn recipient(
        comptime kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        recipient_private_key: []const u8,
        sender_public_key: []const u8,
        enc: []const u8,
        info: []const u8,
        allocator: std.mem.Allocator,
    ) HpkeError!Recipient {
        const ctx = try createRecipient(
            0x02,
            true,
            false,
            kem_id,
            kdf_id,
            aead_id,
            recipient_private_key,
            sender_public_key,
            enc,
            info,
            &[_]u8{},
            &[_]u8{},
            allocator,
        );
        return .{ .context = ctx };
    }
};

/// PSK+Auth mode (combined) - both PSK and sender authentication.
pub const PSKAuthMode = struct {
    pub const Sender = struct {
        context: Context,
        enc: []u8,

        pub fn deinit(self: *Sender, allocator: std.mem.Allocator) void {
            allocator.free(self.enc);
            self.context.deinit(allocator);
            self.* = undefined;
        }
    };

    pub const Recipient = struct {
        context: Context,

        pub fn deinit(self: *Recipient, allocator: std.mem.Allocator) void {
            self.context.deinit(allocator);
            self.* = undefined;
        }
    };

    /// Creates a sender context in PSK+Auth mode.
    ///
    /// - `kem_id`: The KEM to use (must be a DHKEM; hybrid KEMs do not support auth).
    /// - `kdf_id`: The KDF to use.
    /// - `aead_id`: The AEAD to use.
    /// - `sender_private_key`: The sender's static private key.
    /// - `peer_public_key`: The recipient's public key.
    /// - `info`: Application-specific info string.
    /// - `psk`: Pre-shared key material.
    /// - `psk_id`: Identifier for the PSK.
    /// - `io`: I/O backend for random bytes.
    /// - `allocator`: Memory allocator for the returned buffers.
    ///
    /// Returns a `Sender` containing the context and the encapsulated key.
    pub fn sender(
        comptime kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        sender_private_key: []const u8,
        peer_public_key: []const u8,
        info: []const u8,
        psk: []const u8,
        psk_id: []const u8,
        io: std.Io,
        allocator: std.mem.Allocator,
    ) HpkeError!Sender {
        const result = try createSender(
            0x03,
            true,
            true,
            kem_id,
            kdf_id,
            aead_id,
            peer_public_key,
            info,
            sender_private_key,
            psk,
            psk_id,
            io,
            allocator,
        );
        return .{ .context = result.ctx, .enc = result.enc };
    }

    /// Creates a recipient context in PSK+Auth mode.
    ///
    /// - `kem_id`: The KEM to use (must be a DHKEM; hybrid KEMs do not support auth).
    /// - `kdf_id`: The KDF to use.
    /// - `aead_id`: The AEAD to use.
    /// - `recipient_private_key`: The recipient's static private key.
    /// - `sender_public_key`: The sender's public key.
    /// - `enc`: The encapsulated key received from the sender.
    /// - `info`: Application-specific info string.
    /// - `psk`: Pre-shared key material (must match the sender's).
    /// - `psk_id`: Identifier for the PSK (must match the sender's).
    /// - `allocator`: Memory allocator for the returned buffers.
    ///
    /// Returns a `Recipient` containing the context for decryption.
    pub fn recipient(
        comptime kem_id: KemId,
        kdf_id: KdfId,
        aead_id: AeadId,
        recipient_private_key: []const u8,
        sender_public_key: []const u8,
        enc: []const u8,
        info: []const u8,
        psk: []const u8,
        psk_id: []const u8,
        allocator: std.mem.Allocator,
    ) HpkeError!Recipient {
        const ctx = try createRecipient(
            0x03,
            true,
            true,
            kem_id,
            kdf_id,
            aead_id,
            recipient_private_key,
            sender_public_key,
            enc,
            info,
            psk,
            psk_id,
            allocator,
        );
        return .{ .context = ctx };
    }
};
