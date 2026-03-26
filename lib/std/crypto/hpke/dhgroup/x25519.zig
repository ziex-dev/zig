const std = @import("std");
const crypto = std.crypto;
const X25519 = crypto.dh.X25519;

pub const X25519Group = struct {
    pub const public_key_len = X25519.public_length;
    pub const private_key_len = X25519.secret_length;
    pub const shared_len = X25519.shared_length;

    pub fn publicFromPrivate(private_key: [private_key_len]u8) [public_key_len]u8 {
        return X25519.recoverPublicKey(private_key) catch unreachable;
    }

    pub fn dh(private_key: [private_key_len]u8, peer_public_key: [public_key_len]u8) ![shared_len]u8 {
        return X25519.scalarmult(private_key, peer_public_key);
    }
};
