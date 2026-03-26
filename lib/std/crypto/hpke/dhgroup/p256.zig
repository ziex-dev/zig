const std = @import("std");
const crypto = std.crypto;
const P256 = crypto.ecc.P256;

pub const P256Group = struct {
    pub const public_key_len = 65;
    pub const private_key_len = 32;
    pub const shared_len = 32;

    pub fn publicFromPrivate(private_key: [private_key_len]u8) [public_key_len]u8 {
        const point = P256.basePoint.mul(private_key, .big) catch unreachable;
        return point.toUncompressedSec1();
    }

    pub fn dh(private_key: [private_key_len]u8, peer_public_key: [public_key_len]u8) ![shared_len]u8 {
        if (peer_public_key[0] != 0x04) return error.InvalidPeerKey;
        const x = peer_public_key[1..33];
        const y = peer_public_key[33..65];
        const point = try P256.fromSerializedAffineCoordinates(x.*, y.*, .big);
        const shared = try point.mul(private_key, .big);
        const shared_x = shared.affineCoordinates().x;
        return shared_x.toBytes(.big);
    }
};
