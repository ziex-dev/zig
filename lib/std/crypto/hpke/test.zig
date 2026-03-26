//! Test runner for HPKE.

test {
    _ = @import("test/kem.zig");
    _ = @import("test/kdf.zig");
    _ = @import("test/aead.zig");
    _ = @import("test/schedule.zig");
    _ = @import("test/context.zig");
    _ = @import("test/setup.zig");
    _ = @import("test/integration.zig");
}
