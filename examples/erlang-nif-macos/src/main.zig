// Simple Zig NIF module for testing macOS linker issues
const std = @import("std");
const erl = @import("erl_nif.zig");

// Simple NIF function: adds two integers
fn add(env: *erl.ErlNifEnv, argc: c_int, argv: [*c]const erl.ERL_NIF_TERM) callconv(.C) erl.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    // For now, just return an atom to test basic loading
    return erl.make_atom(env, "ok");
}

// NIF function table
const funcs = [_]erl.ErlNifFunc{
    .{
        .name = "add",
        .arity = 2,
        .fptr = &add,
        .flags = 0,
    },
};

// Module load callback
fn load(env: *erl.ErlNifEnv, priv_data: [*c]?*anyopaque, load_info: erl.ERL_NIF_TERM) callconv(.C) c_int {
    _ = env;
    _ = priv_data;
    _ = load_info;
    return 0; // Success
}

// Module upgrade callback  
fn upgrade(env: *erl.ErlNifEnv, priv_data: [*c]?*anyopaque, old_priv_data: [*c]?*anyopaque, load_info: erl.ERL_NIF_TERM) callconv(.C) c_int {
    _ = env;
    _ = priv_data;
    _ = old_priv_data;
    _ = load_info;
    return 0; // Success
}

// NIF entry point - this is what Erlang looks for when loading the module
export var nif_entry = erl.ErlNifEntry{
    .major = 2,
    .minor = 16,
    .name = "zig_test",
    .num_of_funcs = funcs.len,
    .funcs = &funcs,
    .load = &load,
    .reload = null,
    .upgrade = &upgrade,
    .unload = null,
    .deprecated_erl_nif_entry_options = 0,
    .variants = null,
};

// For macOS, we need to export with a specific name pattern
// Erlang looks for: nif_init or _nif_init depending on platform
export fn nif_init() *const erl.ErlNifEntry {
    return &nif_entry;
}
