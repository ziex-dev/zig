const std = @import("std");
const kem = @import("../kem.zig");
const setup = @import("../setup.zig");

const dhkem = kem.dhkem;
const KemId = kem.KemId;

test "HPKE base mode roundtrip with both KEMs" {
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
        const recipient_public = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => std.crypto.dh.X25519.recoverPublicKey(recipient_private) catch unreachable,
            .dhkem_p256_hkdf_sha256 => dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private),
            else => unreachable,
        };

        var sender = try setup.BaseMode.sender(
            kem_id,
            .hkdf_sha256,
            .aes_128_gcm,
            &recipient_public,
            "my_info",
            io,
            allocator,
        );
        defer sender.deinit(allocator);

        var recipient = try setup.BaseMode.recipient(
            kem_id,
            .hkdf_sha256,
            .aes_128_gcm,
            &recipient_private,
            sender.enc,
            "my_info",
            allocator,
        );
        defer recipient.deinit(allocator);

        const plaintext = "Hello, HPKE!";
        const aad = "additional data";

        const ciphertext = try sender.context.seal(allocator, plaintext, aad);
        defer allocator.free(ciphertext);

        const decrypted = try recipient.context.open(allocator, ciphertext, aad);
        defer allocator.free(decrypted);

        try std.testing.expectEqualSlices(u8, plaintext, decrypted);

        const exporter = try sender.context.exportSecret(allocator, "exporter context", 16);
        defer allocator.free(exporter);
        const exporter_recip = try recipient.context.exportSecret(allocator, "exporter context", 16);
        defer allocator.free(exporter_recip);
        try std.testing.expectEqualSlices(u8, exporter, exporter_recip);
    }
}

test "HPKE auth mode roundtrip with X25519" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const sender_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);

    var sender = try setup.AuthMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &sender_kp.secret_key,
        &recipient_kp.public_key,
        "auth_info",
        io,
        allocator,
    );
    defer {
        allocator.free(sender.enc);
        sender.context.deinit(allocator);
    }

    var recipient = try setup.AuthMode.recipient(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_kp.secret_key,
        &sender_kp.public_key,
        sender.enc,
        "auth_info",
        allocator,
    );
    defer recipient.deinit(allocator);

    const plaintext = "Hello, Auth HPKE!";
    const aad = "auth additional data";

    const ciphertext = try sender.context.seal(allocator, plaintext, aad);
    defer allocator.free(ciphertext);

    const decrypted = try recipient.context.open(allocator, ciphertext, aad);
    defer allocator.free(decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, decrypted);

    const exporter = try sender.context.exportSecret(allocator, "auth exporter context", 16);
    defer allocator.free(exporter);
    const exporter_recip = try recipient.context.exportSecret(allocator, "auth exporter context", 16);
    defer allocator.free(exporter_recip);
    try std.testing.expectEqualSlices(u8, exporter, exporter_recip);
}

test "HPKE auth mode roundtrip with P-256" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var sender_seed: [32]u8 = undefined;
    io.random(&sender_seed);
    const sender_private = try dhkem.P256.hkdf.sha256.deriveKeyPair(sender_seed);
    const sender_public = dhkem.P256.hkdf.sha256.publicFromPrivate(sender_private);

    var recipient_seed: [32]u8 = undefined;
    io.random(&recipient_seed);
    const recipient_private = try dhkem.P256.hkdf.sha256.deriveKeyPair(recipient_seed);
    const recipient_public = dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private);

    var sender = try setup.AuthMode.sender(
        .dhkem_p256_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &sender_private,
        &recipient_public,
        "auth_info",
        io,
        allocator,
    );
    defer {
        allocator.free(sender.enc);
        sender.context.deinit(allocator);
    }

    var recipient = try setup.AuthMode.recipient(
        .dhkem_p256_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_private,
        &sender_public,
        sender.enc,
        "auth_info",
        allocator,
    );
    defer recipient.deinit(allocator);

    const plaintext = "Hello, Auth HPKE (P-256)!";
    const aad = "auth additional data";

    const ciphertext = try sender.context.seal(allocator, plaintext, aad);
    defer allocator.free(ciphertext);

    const decrypted = try recipient.context.open(allocator, ciphertext, aad);
    defer allocator.free(decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, decrypted);

    const exporter = try sender.context.exportSecret(allocator, "auth exporter context", 16);
    defer allocator.free(exporter);
    const exporter_recip = try recipient.context.exportSecret(allocator, "auth exporter context", 16);
    defer allocator.free(exporter_recip);
    try std.testing.expectEqualSlices(u8, exporter, exporter_recip);
}

test "HPKE PSK mode roundtrip with both KEMs" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const psk = "my pre-shared secret";
    const psk_id = "example psk id";

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
        const recipient_public = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => std.crypto.dh.X25519.recoverPublicKey(recipient_private) catch unreachable,
            .dhkem_p256_hkdf_sha256 => dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private),
            else => unreachable,
        };

        var sender = try setup.PSKMode.sender(
            kem_id,
            .hkdf_sha256,
            .aes_128_gcm,
            &recipient_public,
            "psk_info",
            psk,
            psk_id,
            io,
            allocator,
        );
        defer sender.deinit(allocator);

        var recipient = try setup.PSKMode.recipient(
            kem_id,
            .hkdf_sha256,
            .aes_128_gcm,
            &recipient_private,
            sender.enc,
            "psk_info",
            psk,
            psk_id,
            allocator,
        );
        defer recipient.deinit(allocator);

        const plaintext = "Hello, PSK HPKE!";
        const aad = "psk additional data";

        const ciphertext = try sender.context.seal(allocator, plaintext, aad);
        defer allocator.free(ciphertext);

        const decrypted = try recipient.context.open(allocator, ciphertext, aad);
        defer allocator.free(decrypted);

        try std.testing.expectEqualSlices(u8, plaintext, decrypted);

        const exporter = try sender.context.exportSecret(allocator, "psk exporter context", 16);
        defer allocator.free(exporter);
        const exporter_recip = try recipient.context.exportSecret(allocator, "psk exporter context", 16);
        defer allocator.free(exporter_recip);
        try std.testing.expectEqualSlices(u8, exporter, exporter_recip);
    }
}

test "HPKE PSK+Auth mode roundtrip with both KEMs" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const psk = "my pre-shared secret for auth";
    const psk_id = "auth psk id";

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
        const sender_public = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => std.crypto.dh.X25519.recoverPublicKey(sender_private) catch unreachable,
            .dhkem_p256_hkdf_sha256 => dhkem.P256.hkdf.sha256.publicFromPrivate(sender_private),
            else => unreachable,
        };
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
        const recipient_public = switch (kem_id) {
            .dhkem_x25519_hkdf_sha256 => std.crypto.dh.X25519.recoverPublicKey(recipient_private) catch unreachable,
            .dhkem_p256_hkdf_sha256 => dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private),
            else => unreachable,
        };

        var sender = try setup.PSKAuthMode.sender(
            kem_id,
            .hkdf_sha256,
            .aes_128_gcm,
            &sender_private,
            &recipient_public,
            "auth_psk_info",
            psk,
            psk_id,
            io,
            allocator,
        );
        defer sender.deinit(allocator);

        var recipient = try setup.PSKAuthMode.recipient(
            kem_id,
            .hkdf_sha256,
            .aes_128_gcm,
            &recipient_private,
            &sender_public,
            sender.enc,
            "auth_psk_info",
            psk,
            psk_id,
            allocator,
        );
        defer recipient.deinit(allocator);

        const plaintext = "Hello, PSK+Auth HPKE!";
        const aad = "auth+psk additional data";

        const ciphertext = try sender.context.seal(allocator, plaintext, aad);
        defer allocator.free(ciphertext);

        const decrypted = try recipient.context.open(allocator, ciphertext, aad);
        defer allocator.free(decrypted);

        try std.testing.expectEqualSlices(u8, plaintext, decrypted);

        const exporter = try sender.context.exportSecret(allocator, "auth+psk exporter context", 16);
        defer allocator.free(exporter);
        const exporter_recip = try recipient.context.exportSecret(allocator, "auth+psk exporter context", 16);
        defer allocator.free(exporter_recip);
        try std.testing.expectEqualSlices(u8, exporter, exporter_recip);
    }
}
