const std = @import("std");
const aead = @import("../aead.zig");
const kdf = @import("../kdf.zig");
const kem = @import("../kem.zig");
const schedule = @import("../schedule.zig");

const KemId = kem.KemId;

fn testKeyScheduleDeterministic() !void {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    const kem_id = KemId.dhkem_x25519_hkdf_sha256;
    const kdf_id = .hkdf_sha256;
    const aead_id = .aes_128_gcm;
    const mode = 0x00;
    const shared_secret = "secret";
    const info = "info";
    const psk = "";
    const psk_id = "";

    const kdf_vtable = &kdf.HkdfSha256Vtable;
    const allocator = std.testing.allocator;

    var material1 = try schedule.KeySchedule.init(mode, kem_id, kdf_id, aead_id, shared_secret, info, psk, psk_id, kdf_vtable, allocator);
    defer material1.deinit(allocator);

    var material2 = try schedule.KeySchedule.init(mode, kem_id, kdf_id, aead_id, shared_secret, info, psk, psk_id, kdf_vtable, allocator);
    defer material2.deinit(allocator);

    try std.testing.expectEqualSlices(u8, material1.key, material2.key);
    try std.testing.expectEqualSlices(u8, material1.base_nonce, material2.base_nonce);
    try std.testing.expectEqualSlices(u8, material1.exporter_secret, material2.exporter_secret);
}

test "keySchedule is deterministic" {
    try testKeyScheduleDeterministic();
}

fn testKeyScheduleWithPsk() !void {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    const kem_id = KemId.dhkem_x25519_hkdf_sha256;
    const kdf_id = .hkdf_sha256;
    const aead_id = .aes_128_gcm;
    const mode = 0x01;
    const shared_secret = "secret";
    const info = "info";
    const psk = "my-psk";
    const psk_id = "my-psk-id";

    const kdf_vtable = &kdf.HkdfSha256Vtable;
    const allocator = std.testing.allocator;

    var material1 = try schedule.KeySchedule.init(mode, kem_id, kdf_id, aead_id, shared_secret, info, psk, psk_id, kdf_vtable, allocator);
    defer material1.deinit(allocator);

    // Change PSK, should get different output.
    var material2 = try schedule.KeySchedule.init(mode, kem_id, kdf_id, aead_id, shared_secret, info, "different-psk", psk_id, kdf_vtable, allocator);
    defer material2.deinit(allocator);

    try std.testing.expect(!std.mem.eql(u8, material1.key, material2.key));
    try std.testing.expect(!std.mem.eql(u8, material1.base_nonce, material2.base_nonce));
    try std.testing.expect(!std.mem.eql(u8, material1.exporter_secret, material2.exporter_secret));

    // Change PSK ID, should also change.
    var material3 = try schedule.KeySchedule.init(mode, kem_id, kdf_id, aead_id, shared_secret, info, psk, "different-id", kdf_vtable, allocator);
    defer material3.deinit(allocator);

    try std.testing.expect(!std.mem.eql(u8, material1.key, material3.key));
}

test "keySchedule output lengths match AEAD" {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    const kem_id = KemId.dhkem_x25519_hkdf_sha256;
    const kdf_id = .hkdf_sha256;
    const aead_id = .aes_128_gcm;
    const mode = 0x00;
    const shared_secret = "secret";
    const info = "info";
    const psk = "";
    const psk_id = "";

    const kdf_vtable = &kdf.HkdfSha256Vtable;
    const allocator = std.testing.allocator;

    var material = try schedule.KeySchedule.init(mode, kem_id, kdf_id, aead_id, shared_secret, info, psk, psk_id, kdf_vtable, allocator);
    defer material.deinit(allocator);

    try std.testing.expectEqual(aead.Aes128Gcm.key_len, material.key.len);
    try std.testing.expectEqual(aead.Aes128Gcm.nonce_len, material.base_nonce.len);
    try std.testing.expectEqual(kdf_vtable.hash_len, material.exporter_secret.len);
}

test "keySchedule with empty info" {
    var threaded = std.Io.Threaded.init_single_threaded;
    _ = threaded.io();

    const kem_id = KemId.dhkem_x25519_hkdf_sha256;
    const kdf_id = .hkdf_sha256;
    const aead_id = .aes_128_gcm;
    const mode = 0x00;
    const shared_secret = "secret";
    const info = "";
    const psk = "";
    const psk_id = "";

    const kdf_vtable = &kdf.HkdfSha256Vtable;
    const allocator = std.testing.allocator;

    var material = try schedule.KeySchedule.init(mode, kem_id, kdf_id, aead_id, shared_secret, info, psk, psk_id, kdf_vtable, allocator);
    defer material.deinit(allocator);

    // Should not panic; just verify lengths.
    try std.testing.expect(material.key.len == aead.Aes128Gcm.key_len);
    try std.testing.expect(material.base_nonce.len == aead.Aes128Gcm.nonce_len);
    try std.testing.expect(material.exporter_secret.len == kdf_vtable.hash_len);
}
