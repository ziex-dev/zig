const std = @import("std");
const setup = @import("../setup.zig");

test "Context: seal/open roundtrip" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    // Generate recipient key pair.
    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_private = recipient_kp.secret_key;
    const recipient_public = recipient_kp.public_key;

    // Sender setup.
    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    // Recipient setup.
    var recipient = try setup.BaseMode.recipient(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_private,
        sender.enc,
        "info",
        allocator,
    );
    defer recipient.deinit(allocator);

    const plaintext = "Hello, world!";
    const aad = "some aad";
    const ciphertext = try sender.context.seal(allocator, plaintext, aad);
    defer allocator.free(ciphertext);

    const decrypted = try recipient.context.open(allocator, ciphertext, aad);
    defer allocator.free(decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, decrypted);
}

test "Context: multiple messages" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_private = recipient_kp.secret_key;
    const recipient_public = recipient_kp.public_key;

    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    var recipient = try setup.BaseMode.recipient(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_private,
        sender.enc,
        "info",
        allocator,
    );
    defer recipient.deinit(allocator);

    const messages = [_][]const u8{ "first", "second", "third", "fourth", "fifth" };
    var ciphertexts: [5][]u8 = undefined;
    defer {
        for (ciphertexts) |ct| if (ct.len > 0) allocator.free(ct);
    }

    for (messages, 0..) |msg, i| {
        const aad = "aad for message {d}";
        const ct = try sender.context.seal(allocator, msg, aad);
        ciphertexts[i] = ct;
    }

    for (messages, 0..) |msg, i| {
        const aad = "aad for message {d}";
        const decrypted = try recipient.context.open(allocator, ciphertexts[i], aad);
        defer allocator.free(decrypted);
        try std.testing.expectEqualSlices(u8, msg, decrypted);
    }
}

test "Context: exporter works" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_private = recipient_kp.secret_key;
    const recipient_public = recipient_kp.public_key;

    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    var recipient = try setup.BaseMode.recipient(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_private,
        sender.enc,
        "info",
        allocator,
    );
    defer recipient.deinit(allocator);

    const context = "exporter context";
    const length = 32;
    const exporter1 = try sender.context.exportSecret(allocator, context, length);
    defer allocator.free(exporter1);
    const exporter2 = try recipient.context.exportSecret(allocator, context, length);
    defer allocator.free(exporter2);

    try std.testing.expectEqualSlices(u8, exporter1, exporter2);
}

test "Context: exporter after sealing" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_public = recipient_kp.public_key;

    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    // Seal a message first.
    const plaintext = "Hello";
    const aad = "aad";
    const ciphertext = try sender.context.seal(allocator, plaintext, aad);
    defer allocator.free(ciphertext);

    // Now export.
    const exporter = try sender.context.exportSecret(allocator, "context after seal", 16);
    defer allocator.free(exporter);
    try std.testing.expect(exporter.len == 16);
}

test "Context: wrong tag fails" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_private = recipient_kp.secret_key;
    const recipient_public = recipient_kp.public_key;

    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    var recipient = try setup.BaseMode.recipient(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_private,
        sender.enc,
        "info",
        allocator,
    );
    defer recipient.deinit(allocator);

    const plaintext = "Hello";
    const aad = "aad";
    const ciphertext = try sender.context.seal(allocator, plaintext, aad);
    defer allocator.free(ciphertext);

    // Corrupt the ciphertext by flipping a byte.
    var corrupted = try allocator.dupe(u8, ciphertext);
    defer allocator.free(corrupted);
    if (corrupted.len > 0) corrupted[0] ^= 0xFF;

    const result = recipient.context.open(allocator, corrupted, aad);
    try std.testing.expectError(error.DecryptionFailed, result);
}

test "Context: cannot open from sender context" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_public = recipient_kp.public_key;

    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    const dummy_ciphertext = try allocator.alloc(u8, 32);
    defer allocator.free(dummy_ciphertext);
    const result = sender.context.open(allocator, dummy_ciphertext, "");
    try std.testing.expectError(error.InvalidContext, result);
}

test "Context: cannot seal from recipient context" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_private = recipient_kp.secret_key;
    const recipient_public = recipient_kp.public_key;

    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    var recipient = try setup.BaseMode.recipient(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_private,
        sender.enc,
        "info",
        allocator,
    );
    defer recipient.deinit(allocator);

    const result = recipient.context.seal(allocator, "plaintext", "aad");
    try std.testing.expectError(error.InvalidContext, result);
}

test "Context: exportSecret with different lengths" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_private = recipient_kp.secret_key;
    const recipient_public = recipient_kp.public_key;

    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    var recipient = try setup.BaseMode.recipient(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_private,
        sender.enc,
        "info",
        allocator,
    );
    defer recipient.deinit(allocator);

    const context = "test context";
    const len1 = 1;
    const len2 = 64;
    const len3 = 256;

    const ex1 = try sender.context.exportSecret(allocator, context, len1);
    defer allocator.free(ex1);
    const ex2 = try sender.context.exportSecret(allocator, context, len2);
    defer allocator.free(ex2);
    const ex3 = try sender.context.exportSecret(allocator, context, len3);
    defer allocator.free(ex3);

    try std.testing.expect(ex1.len == len1);
    try std.testing.expect(ex2.len == len2);
    try std.testing.expect(ex3.len == len3);

    const ex1_recip = try recipient.context.exportSecret(allocator, context, len1);
    defer allocator.free(ex1_recip);
    try std.testing.expectEqualSlices(u8, ex1, ex1_recip);
}

test "Context: sequence overflow returns error" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();

    // Generate a recipient key pair.
    const recipient_kp = std.crypto.dh.X25519.KeyPair.generate(io);
    const recipient_public = recipient_kp.public_key;

    // Create a sender context.
    var sender = try setup.BaseMode.sender(
        .dhkem_x25519_hkdf_sha256,
        .hkdf_sha256,
        .aes_128_gcm,
        &recipient_public,
        "info",
        io,
        allocator,
    );
    defer sender.deinit(allocator);

    // Set the sequence number to the maximum value minus one.
    sender.context.seq = std.math.maxInt(u64) - 1;

    // First seal should succeed.
    const ciphertext = try sender.context.seal(allocator, "Hello", "");
    defer allocator.free(ciphertext);

    // Second seal should overflow.
    const result = sender.context.seal(allocator, "World", "");
    try std.testing.expectError(error.SequenceOverflow, result);
}
