const std = @import("std");
const kem = @import("../kem.zig");

const dhkem = kem.dhkem;

test "X25519 KEM: deriveKeyPair returns seed unchanged" {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();
    var seed: [32]u8 = undefined;
    io.random(&seed);
    const derived = try dhkem.X25519.hkdf.sha256.deriveKeyPair(seed);
    try std.testing.expectEqualSlices(u8, &seed, &derived);
}

test "X25519 KEM: publicFromPrivate roundtrip" {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();
    var private: [32]u8 = undefined;
    io.random(&private);
    const public = dhkem.X25519.hkdf.sha256.publicFromPrivate(private);
    const recovered = try std.crypto.dh.X25519.recoverPublicKey(private);
    try std.testing.expectEqualSlices(u8, &public, &recovered);
}

test "X25519 KEM: encaps/decaps roundtrip" {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_public = recipient_kp.public_key;
    const recipient_private = recipient_kp.secret_key;

    var seed: [32]u8 = undefined;
    io.random(&seed);
    const encap = try dhkem.X25519.hkdf.sha256.encaps(recipient_public, seed);
    const shared = try dhkem.X25519.hkdf.sha256.decaps(recipient_private, encap.enc);

    try std.testing.expectEqualSlices(u8, &encap.shared_secret, &shared);
}

// -----------------------------------------------------------------------------
// P-256 KEM tests
// -----------------------------------------------------------------------------

test "P256 KEM: deriveKeyPair produces non-zero scalar" {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var seed: [32]u8 = undefined;
    io.random(&seed);
    const private = try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
    const scalar = std.crypto.ecc.P256.scalar.Scalar.fromBytes(private, .big) catch unreachable;
    try std.testing.expect(!scalar.isZero());
}

test "P256 KEM: publicFromPrivate roundtrip" {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var seed: [32]u8 = undefined;
    io.random(&seed);
    const private = try dhkem.P256.hkdf.sha256.deriveKeyPair(seed);
    const public_bytes = dhkem.P256.hkdf.sha256.publicFromPrivate(private);

    const point = try std.crypto.ecc.P256.fromSec1(&public_bytes);
    const affine = point.affineCoordinates();
    try std.testing.expect(!affine.x.isZero());
    try std.testing.expect(!affine.y.isZero());
}

test "P256 KEM: encaps/decaps roundtrip" {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var recipient_seed: [32]u8 = undefined;
    io.random(&recipient_seed);
    const recipient_private = try dhkem.P256.hkdf.sha256.deriveKeyPair(recipient_seed);
    const recipient_public = dhkem.P256.hkdf.sha256.publicFromPrivate(recipient_private);

    var seed: [32]u8 = undefined;
    io.random(&seed);
    const encap = try dhkem.P256.hkdf.sha256.encaps(recipient_public, seed);
    const shared = try dhkem.P256.hkdf.sha256.decaps(recipient_private, encap.enc);

    try std.testing.expectEqualSlices(u8, &encap.shared_secret, &shared);
}

test "P256 KEM: encaps with invalid public key returns InvalidPeerKey" {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var invalid_public: [65]u8 = undefined;
    io.random(&invalid_public);
    invalid_public[0] = 0x02; // Invalid uncompressed point prefix.

    var seed: [32]u8 = undefined;
    io.random(&seed);
    const result = dhkem.P256.hkdf.sha256.encaps(invalid_public, seed);
    try std.testing.expectError(error.InvalidPeerKey, result);
}

test "P256 KEM: decaps with invalid ciphertext returns InvalidPeerKey" {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var recipient_seed: [32]u8 = undefined;
    io.random(&recipient_seed);
    const recipient_private = try dhkem.P256.hkdf.sha256.deriveKeyPair(recipient_seed);

    var invalid_enc: [65]u8 = undefined;
    io.random(&invalid_enc);
    invalid_enc[0] = 0x04; // Keep first byte correct to pass basic check.
    const result = dhkem.P256.hkdf.sha256.decaps(recipient_private, invalid_enc);
    try std.testing.expectError(error.InvalidPeerKey, result);
}

// -----------------------------------------------------------------------------
// Hybrid KEM tests
// -----------------------------------------------------------------------------
test "Hybrid KEM: encaps/decaps roundtrip" {
    inline for (.{
        kem.XWing,
        kem.MlKem768P256,
        kem.MlKem1024P384,
    }) |Kem| {
        var threaded = std.Io.Threaded.init_single_threaded;
        const io = threaded.io();

        // Generate a key pair.
        var seed: [Kem.key_seed_len]u8 = undefined;
        io.random(&seed);
        const private = try Kem.deriveKeyPair(seed);
        const public = Kem.publicFromPrivate(private);

        // Encapsulate.
        var encap_seed: [Kem.encap_seed_len]u8 = undefined;
        io.random(&encap_seed);
        const encap = try Kem.encaps(public, encap_seed);
        // Decapsulate.
        const shared = try Kem.decaps(private, encap.enc);

        try std.testing.expectEqualSlices(u8, &encap.shared_secret, &shared);
    }
}
