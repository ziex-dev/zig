# Zig NIF Example for macOS

This directory contains a minimal working example of a Zig NIF (Native Implemented Function for Erlang/Elixir) that builds successfully on macOS.

## Known Issues

There are **two linker-related issues** when building Zig NIFs on macOS:

1. **NIF Symbol Resolution** (Primary): NIFs reference Erlang VM functions that are resolved at runtime. On macOS, this requires special linker flags (`-fallow-shlib-undefined`).

2. **Build Runner Issue** (Secondary): On macOS 26.3.1+, `zig build` fails due to build runner linking issues. Use `build_nif.sh` as a workaround.

See [NIF_MACOS_LINKER_INVESTIGATION.md](../NIF_MACOS_LINKER_INVESTIGATION.md) for full details.

## Files

- `src/erl_nif.zig` - Zig bindings for Erlang NIF API
- `src/main.zig` - Simple NIF implementation
- `build.zig` - Zig build configuration (documented, may not work on macOS 26.3.1+)
- `build_nif.sh` - Shell script workaround for building NIFs

## Building

### Option 1: Using the shell script (Recommended)

```bash
./build_nif.sh
```

This will create `zig_test.so` ready to load from Erlang/Elixir.

### Option 2: Direct command line

```bash
zig build-lib -dynamic -target native-macos -lc -fallow-shlib-undefined -OReleaseSafe -o zig_test.so src/main.zig
```

### Option 3: Using zig build (may fail on macOS 26.3.1+)

```bash
zig build
```

## Usage from Erlang/Elixir

Once built, the NIF can be loaded from Erlang:

```erlang
-module(zig_test).
-on_load(init/0).

init() ->
    Path = filename:join(code:priv_dir(my_app), "zig_test"),
    ok = erlang:load_nif(Path, 0).

add(_A, _B) ->
    erlang:nif_error(nif_not_loaded).
```

## What This Demonstrates

1. **Zig NIF Structure**: How to write a basic NIF in Zig
2. **macOS Linker Flags**: The required `-fallow-shlib-undefined` flag for macOS NIFs
3. **Erlang NIF API Bindings**: Minimal bindings to the `erl_nif.h` API
4. **Workaround for Build Issues**: Alternative build methods when `zig build` fails

## Troubleshooting

### "undefined symbol: _enif_make_*"

You're missing the `-fallow-shlib-undefined` flag. Use one of the build methods above that includes this flag.

### Build runner errors on macOS

If you see errors about `_posix_memalign`, `_exit`, `_abort`, etc. from `build.o`, you're hitting the build runner issue. Use `build_nif.sh` instead of `zig build`.

## Further Reading

- [Erlang NIF Documentation](https://www.erlang.org/doc/tutorial/nif.html)
- [Zig Documentation - C Interop](https://ziglang.org/documentation/master/#C-Interoperability)
- [Zig Issue #22038 - Weak symbols on macOS](https://github.com/ziglang/zig/issues/22038)
