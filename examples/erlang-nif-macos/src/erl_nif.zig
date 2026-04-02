// Erlang NIF API bindings for Zig
// Based on erl_nif.h from Erlang/OTP

const std = @import("std");

// Opaque types
pub const ERL_NIF_TERM = usize;
pub const ErlNifEnv = opaque {};
pub const ErlNifFunc = extern struct {
    name: [*c]const u8,
    arity: c_uint,
    fptr: *const fn (*ErlNifEnv, c_int, [*c]const ERL_NIF_TERM) callconv(.C) ERL_NIF_TERM,
    flags: c_uint,
};

pub const ErlNifEntry = extern struct {
    major: c_int,
    minor: c_int,
    name: [*c]const u8,
    num_of_funcs: c_int,
    funcs: [*c]const ErlNifFunc,
    load: ?*const fn (*ErlNifEnv, [*c]?*anyopaque, ERL_NIF_TERM) callconv(.C) c_int,
    reload: ?*const fn (*ErlNifEnv, [*c]?*anyopaque, ERL_NIF_TERM) callconv(.C) c_int,
    upgrade: ?*const fn (*ErlNifEnv, [*c]?*anyopaque, [*c]?*anyopaque, ERL_NIF_TERM) callconv(.C) c_int,
    unload: ?*const fn (*ErlNifEnv, ?*anyopaque) callconv(.C) void,
    deprecated_erl_nif_entry_options: c_int,
    variants: ?*anyopaque,
};

// External functions from Erlang VM (loaded dynamically)
extern fn enif_make_int(env: *ErlNifEnv, i: c_int) ERL_NIF_TERM;
extern fn enif_make_atom(env: *ErlNifEnv, name: [*c]const u8) ERL_NIF_TERM;

// Wrapper functions
pub fn make_int(env: *ErlNifEnv, i: c_int) ERL_NIF_TERM {
    return enif_make_int(env, i);
}

pub fn make_atom(env: *ErlNifEnv, name: [*c]const u8) ERL_NIF_TERM {
    return enif_make_atom(env, name);
}
