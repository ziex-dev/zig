const std = @import("std");
const kem = @import("../kem.zig");
const setup = @import("../setup.zig");

const dhkem = kem.dhkem;
const KemId = kem.KemId;

test "BaseMode sender: invalid public key length" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        // Generate a valid key pair.
        const valid_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const valid_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(valid_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(valid_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const valid_public = valid_public_ptr[0..];

        // Test with invalid public key length.
        var invalid_public = try allocator.alloc(u8, valid_public.len + 1);
        defer allocator.free(invalid_public);
        @memcpy(invalid_public[0..valid_public.len], valid_public);
        invalid_public[valid_public.len] = 0;

        const result = setup.BaseMode.sender(kem_id, .hkdf_sha256, .aes_128_gcm, invalid_public, "info", io, allocator);
        try std.testing.expectError(error.InvalidKeyLength, result);
    }
}

test "BaseMode recipient: invalid private key length" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        // Generate a valid key pair and enc.
        const valid_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const valid_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(valid_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(valid_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const valid_public = valid_public_ptr[0..];
        var seed: [32]u8 = undefined;
        io.random(&seed);
        const encap = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => try dhkem.X25519.hkdf.sha256.encaps(valid_public[0..dhkem.X25519.hkdf.sha256.public_key_len].*, seed),
            .dhkem_p256_hkdf_sha256 => try dhkem.P256.hkdf.sha256.encaps(valid_public[0..dhkem.P256.hkdf.sha256.public_key_len].*, seed),
            else => unreachable,
        };
        const enc = encap.enc;

        // Test with invalid private key length.
        var invalid_private = try allocator.alloc(u8, valid_private.len + 1);
        defer allocator.free(invalid_private);
        @memcpy(invalid_private[0..valid_private.len], &valid_private);
        invalid_private[valid_private.len] = 0;

        const result = setup.BaseMode.recipient(kem_id, .hkdf_sha256, .aes_128_gcm, invalid_private, &enc, "info", allocator);
        try std.testing.expectError(error.InvalidKeyLength, result);
    }
}

test "BaseMode recipient: invalid enc length" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        const kem_len: usize = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => dhkem.X25519.hkdf.sha256.enc_len,
            .dhkem_p256_hkdf_sha256 => dhkem.P256.hkdf.sha256.enc_len,
            else => unreachable,
        };
        // Generate a valid private key.
        const valid_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };

        // Invalid enc length.
        const invalid_enc = try allocator.alloc(u8, kem_len + 1);
        defer allocator.free(invalid_enc);
        @memset(invalid_enc, 0);

        const result = setup.BaseMode.recipient(kem_id, .hkdf_sha256, .aes_128_gcm, &valid_private, invalid_enc, "info", allocator);
        try std.testing.expectError(error.InvalidKeyLength, result);
    }
}

test "BaseMode sender: invalid public key format (P-256 only)" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const kem_id = KemId.dhkem_p256_hkdf_sha256;
    // Generate a valid public key.
    var seed: [32]u8 = undefined;
    io.random(&seed);
    const private = try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
    var public = dhkem.P256.hkdf.sha256.publicFromPrivate(private);
    // Corrupt the public key: change the first byte to 0x02 (compressed point) - invalid for our parser.
    public[0] = 0x02;

    const result = setup.BaseMode.sender(kem_id, .hkdf_sha256, .aes_128_gcm, &public, "info", io, allocator);
    try std.testing.expectError(error.InvalidPeerKey, result);
}

test "PSK sender/recipient: empty PSK and PSK ID allowed" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        const recipient_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const recipient_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(recipient_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const recipient_public = recipient_public_ptr[0..];

        // PSK with empty PSK and empty PSK ID.
        var sender = try setup.PSKMode.sender(kem_id, .hkdf_sha256, .aes_128_gcm, recipient_public, "info", "", "", io, allocator);
        defer sender.deinit(allocator);
        var recipient = try setup.PSKMode.recipient(kem_id, .hkdf_sha256, .aes_128_gcm, &recipient_private, sender.enc, "info", "", "", allocator);
        defer recipient.deinit(allocator);

        const plaintext = "test";
        const aad = "";
        const ciphertext = try sender.context.seal(allocator, plaintext, aad);
        defer allocator.free(ciphertext);
        const decrypted = try recipient.context.open(allocator, ciphertext, aad);
        defer allocator.free(decrypted);
        try std.testing.expectEqualSlices(u8, plaintext, decrypted);
    }
}

test "AuthMode sender: invalid sender private key length" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        const valid_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const valid_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(valid_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(valid_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const valid_public = valid_public_ptr[0..];

        var invalid_private = try allocator.alloc(u8, valid_private.len + 1);
        defer allocator.free(invalid_private);
        @memcpy(invalid_private[0..valid_private.len], &valid_private);
        invalid_private[valid_private.len] = 0;

        const result = setup.AuthMode.sender(kem_id, .hkdf_sha256, .aes_128_gcm, invalid_private, valid_public, "info", io, allocator);
        try std.testing.expectError(error.InvalidKeyLength, result);
    }
}

test "AuthMode recipient: invalid recipient private key length" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        // Generate valid sender and recipient keys.
        const sender_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const sender_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(sender_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(sender_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const sender_public = sender_public_ptr[0..];
        const recipient_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const recipient_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(recipient_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const recipient_public = recipient_public_ptr[0..];

        // Encapsulate to get enc.
        var seed: [32]u8 = undefined;
        io.random(&seed);
        const encap = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => try dhkem.X25519.hkdf.sha256.authEncap(sender_private, recipient_public[0..dhkem.X25519.hkdf.sha256.public_key_len].*, seed),
            .dhkem_p256_hkdf_sha256 => try dhkem.P256.hkdf.sha256.authEncap(sender_private, recipient_public[0..dhkem.P256.hkdf.sha256.public_key_len].*, seed),
            else => unreachable,
        };
        const enc = encap.enc;

        // Invalid recipient private key length.
        var invalid_private = try allocator.alloc(u8, recipient_private.len + 1);
        defer allocator.free(invalid_private);
        @memcpy(invalid_private[0..recipient_private.len], &recipient_private);
        invalid_private[recipient_private.len] = 0;

        const result = setup.AuthMode.recipient(kem_id, .hkdf_sha256, .aes_128_gcm, invalid_private, sender_public, &enc, "info", allocator);
        try std.testing.expectError(error.InvalidKeyLength, result);
    }
}

test "AuthMode recipient: invalid sender public key length" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        const sender_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const sender_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(sender_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(sender_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const sender_public = sender_public_ptr[0..];
        const recipient_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const recipient_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(recipient_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const recipient_public = recipient_public_ptr[0..];

        var seed: [32]u8 = undefined;
        io.random(&seed);
        const encap = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => try dhkem.X25519.hkdf.sha256.authEncap(sender_private, recipient_public[0..dhkem.X25519.hkdf.sha256.public_key_len].*, seed),
            .dhkem_p256_hkdf_sha256 => try dhkem.P256.hkdf.sha256.authEncap(sender_private, recipient_public[0..dhkem.P256.hkdf.sha256.public_key_len].*, seed),
            else => unreachable,
        };
        const enc = encap.enc;

        // Invalid sender public key length.
        var invalid_sender = try allocator.alloc(u8, sender_public.len + 1);
        defer allocator.free(invalid_sender);
        @memcpy(invalid_sender[0..sender_public.len], sender_public);
        invalid_sender[sender_public.len] = 0;

        const result = setup.AuthMode.recipient(kem_id, .hkdf_sha256, .aes_128_gcm, &recipient_private, invalid_sender, &enc, "info", allocator);
        try std.testing.expectError(error.InvalidKeyLength, result);
    }
}

test "AuthMode recipient: invalid enc length" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        const sender_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const sender_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(sender_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(sender_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const sender_public = sender_public_ptr[0..];
        const recipient_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const recipient_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(recipient_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const recipient_public = recipient_public_ptr[0..];

        var seed: [32]u8 = undefined;
        io.random(&seed);
        const encap = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => try dhkem.X25519.hkdf.sha256.authEncap(sender_private, recipient_public[0..dhkem.X25519.hkdf.sha256.public_key_len].*, seed),
            .dhkem_p256_hkdf_sha256 => try dhkem.P256.hkdf.sha256.authEncap(sender_private, recipient_public[0..dhkem.P256.hkdf.sha256.public_key_len].*, seed),
            else => unreachable,
        };
        const enc = encap.enc;

        // Invalid enc length.
        var invalid_enc = try allocator.alloc(u8, enc.len + 1);
        defer allocator.free(invalid_enc);
        @memcpy(invalid_enc[0..enc.len], &enc);
        invalid_enc[enc.len] = 0;

        const result = setup.AuthMode.recipient(kem_id, .hkdf_sha256, .aes_128_gcm, &recipient_private, sender_public, invalid_enc, "info", allocator);
        try std.testing.expectError(error.InvalidKeyLength, result);
    }
}

test "PSK+Auth sender/recipient: error propagation" {
    // This test ensures the PSK+Auth functions are present and don't crash on valid inputs.
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    inline for (.{ KemId.dhkem_x25519_hkdf_sha256, KemId.dhkem_p256_hkdf_sha256 }) |kem_id| {
        const sender_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const sender_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(sender_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(sender_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const sender_public = sender_public_ptr[0..];
        const recipient_private: [32]u8 = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const kp = std.crypto.dh.X25519.KeyPair.generate(io);
                break :blk kp.secret_key;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                var seed: [32]u8 = undefined;
                io.random(&seed);
                break :blk try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
            },
            else => unreachable,
        };
        const recipient_public_ptr = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => blk: {
                const pub_arr = std.crypto.dh.X25519.recoverPublicKey(recipient_private) catch unreachable;
                break :blk &pub_arr;
            },
            .dhkem_p256_hkdf_sha256 => blk: {
                const pub_arr = dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private);
                break :blk &pub_arr;
            },
            else => unreachable,
        };
        const recipient_public = recipient_public_ptr[0..];

        const psk = "psk";
        const psk_id = "id";
        const info = "info";

        var sender = try setup.PSKAuthMode.sender(kem_id, .hkdf_sha256, .aes_128_gcm, &sender_private, recipient_public, info, psk, psk_id, io, allocator);
        defer sender.deinit(allocator);
        var recipient = try setup.PSKAuthMode.recipient(kem_id, .hkdf_sha256, .aes_128_gcm, &recipient_private, sender_public, sender.enc, info, psk, psk_id, allocator);
        defer recipient.deinit(allocator);

        const plaintext = "test";
        const aad = "";
        const ciphertext = try sender.context.seal(allocator, plaintext, aad);
        defer allocator.free(ciphertext);
        const decrypted = try recipient.context.open(allocator, ciphertext, aad);
        defer allocator.free(decrypted);
        try std.testing.expectEqualSlices(u8, plaintext, decrypted);
    }
}
