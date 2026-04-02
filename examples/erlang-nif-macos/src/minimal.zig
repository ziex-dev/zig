// Minimal NIF that doesn't reference Erlang functions
const std = @import("std");

// Simple NIF function that just returns a number (no Erlang API calls)
fn test_func(env: ?*anyopaque, argc: c_int, argv: [*c]usize) callconv(.C) usize {
    _ = env;
    _ = argc;
    _ = argv;
    return 42; // Just return 42 directly
}

const ErlNifFunc = extern struct {
    name: [*c]const u8,
    arity: c_uint,
    fptr: *const fn (?*anyopaque, c_int, [*c]usize) callconv(.C) usize,
    flags: c_uint,
};

const ErlNifEntry = extern struct {
    major: c_int,
    minor: c_int,
    name: [*c]const u8,
    num_of_funcs: c_int,
    funcs: [*c]const ErlNifFunc,
    load: ?*anyopaque,
    reload: ?*anyopaque,
    upgrade: ?*anyopaque,
    unload: ?*anyopaque,
    deprecated_erl_nif_entry_options: c_int,
    variants: ?*anyopaque,
};

var funcs = [_]ErlNifFunc{
    .{
        .name = "test_func",
        .arity = 0,
        .fptr = &test_func,
        .flags = 0,
    },
};

export var nif_entry = ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = "test_nif",
    .num_of_funcs = 1,
    .funcs = &funcs,
    .load = null,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .deprecated_erl_nif_entry_options = 0,
    .variants = null,
};

export fn nif_init() *const ErlNifEntry {
    return &nif_entry;
}
