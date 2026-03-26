const std = @import("std");
const aead = @import("../aead.zig");

fn testAeadRoundtrip(comptime Aead: type) !void {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var key: [Aead.key_len]u8 = undefined;
    var nonce: [Aead.nonce_len]u8 = undefined;
    io.random(&key);
    io.random(&nonce);

    const plaintext = "Hello, AEAD!";
    const aad = "associated data";
    var ciphertext: [plaintext.len]u8 = undefined;
    var tag: [Aead.tag_len]u8 = undefined;

    // Seal
    try Aead.seal(key, nonce, aad, plaintext, &ciphertext, &tag);

    // Open
    var decrypted: [plaintext.len]u8 = undefined;
    try Aead.open(key, nonce, aad, &ciphertext, &tag, &decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, &decrypted);
}

fn testAeadWrongKey(comptime Aead: type) !void {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var key: [Aead.key_len]u8 = undefined;
    var wrong_key: [Aead.key_len]u8 = undefined;
    var nonce: [Aead.nonce_len]u8 = undefined;
    io.random(&key);
    io.random(&wrong_key);
    io.random(&nonce);

    const plaintext = "Hello, AEAD!";
    const aad = "associated data";
    var ciphertext: [plaintext.len]u8 = undefined;
    var tag: [Aead.tag_len]u8 = undefined;

    try Aead.seal(key, nonce, aad, plaintext, &ciphertext, &tag);

    var decrypted: [plaintext.len]u8 = undefined;
    const result = Aead.open(wrong_key, nonce, aad, &ciphertext, &tag, &decrypted);
    try std.testing.expectError(error.DecryptionFailed, result);
}

fn testAeadWrongTag(comptime Aead: type) !void {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var key: [Aead.key_len]u8 = undefined;
    var nonce: [Aead.nonce_len]u8 = undefined;
    io.random(&key);
    io.random(&nonce);

    const plaintext = "Hello, AEAD!";
    const aad = "associated data";
    var ciphertext: [plaintext.len]u8 = undefined;
    var tag: [Aead.tag_len]u8 = undefined;

    try Aead.seal(key, nonce, aad, plaintext, &ciphertext, &tag);

    // Corrupt the tag
    tag[0] ^= 0xFF;

    var decrypted: [plaintext.len]u8 = undefined;
    const result = Aead.open(key, nonce, aad, &ciphertext, &tag, &decrypted);
    try std.testing.expectError(error.DecryptionFailed, result);
}

fn testAeadEmpty(comptime Aead: type) !void {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    var key: [Aead.key_len]u8 = undefined;
    var nonce: [Aead.nonce_len]u8 = undefined;
    io.random(&key);
    io.random(&nonce);

    const plaintext = "";
    const aad = "";
    var ciphertext: [0]u8 = undefined;
    var tag: [Aead.tag_len]u8 = undefined;

    try Aead.seal(key, nonce, aad, plaintext, &ciphertext, &tag);

    var decrypted: [0]u8 = undefined;
    try Aead.open(key, nonce, aad, &ciphertext, &tag, &decrypted);
    // Should succeed
}

test "AEAD: AES-128-GCM roundtrip" {
    try testAeadRoundtrip(aead.Aes128Gcm);
    try testAeadWrongKey(aead.Aes128Gcm);
    try testAeadWrongTag(aead.Aes128Gcm);
    try testAeadEmpty(aead.Aes128Gcm);
}

test "AEAD: AES-256-GCM roundtrip" {
    try testAeadRoundtrip(aead.Aes256Gcm);
    try testAeadWrongKey(aead.Aes256Gcm);
    try testAeadWrongTag(aead.Aes256Gcm);
    try testAeadEmpty(aead.Aes256Gcm);
}

test "AEAD: ChaCha20-Poly1305 roundtrip" {
    try testAeadRoundtrip(aead.ChaCha20Poly1305);
    try testAeadWrongKey(aead.ChaCha20Poly1305);
    try testAeadWrongTag(aead.ChaCha20Poly1305);
    try testAeadEmpty(aead.ChaCha20Poly1305);
}
