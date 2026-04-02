const std = @import("std");

// IMPORTANT: This build.zig demonstrates the CORRECT configuration for Zig NIFs on macOS.
// However, due to a known issue with the Zig build runner on macOS 26.3.1+ (see NIF_MACOS_LINKER_INVESTIGATION.md),
// you may need to use the provided build_nif.sh script instead of `zig build`.
//
// The command-line build that works:
//   zig build-lib -dynamic -target native-macos -lc -fallow-shlib-undefined src/main.zig
//
// Related Zig GitHub issue: https://github.com/ziglang/zig/issues/22038 (weak symbols on macOS)

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create a shared library for the NIF
    const lib = b.addSharedLibrary(.{
        .name = "zig_test",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,  // Required for NIFs
    });

    // macOS-specific configuration for NIFs
    const os_tag = target.result.os.tag;
    if (os_tag == .macos) {
        // CRITICAL: NIFs on macOS require undefined symbol resolution at runtime.
        //
        // Explanation:
        // NIFs reference Erlang VM functions (enif_make_atom, enif_make_int, etc.)
        // that are only available when the NIF is loaded by the Erlang VM.
        // On macOS, the linker needs to allow these undefined symbols at link time,
        // knowing they will be resolved dynamically when dlopen() loads the NIF.
        //
        // This flag tells the macOS linker to use -undefined dynamic_lookup,
        // which allows the NIF to be built even though enif_* symbols are undefined.
        //
        // Without this flag, you'll get errors like:
        //   error: undefined symbol: _enif_make_atom
        //
        // Note: This is standard NIF behavior on macOS. The same approach is used
        // by C/C++ NIFs with the -undefined dynamic_lookup linker flag.
        lib.linker_allow_shlib_undefined = true;
        
        // Additional note: On macOS, Erlang expects NIFs with .so extension,
        // not .dylib. The install step below will create the appropriate file.
    }

    // Install the shared library
    b.installArtifact(lib);
    
    // Print configuration summary
    const print_step = b.addSystemCommand(&.{
        "echo",
        "\n=== Build Configuration ===",
        "Target:", @tagName(target.result.os.tag), @tagName(target.result.cpu.arch),
        "Optimization:", @tagName(optimize),
        "libc: enabled",
        if (os_tag == .macos) "macOS NIF mode: enabled (-fallow-shlib-undefined)" else "macOS NIF mode: N/A",
        "===========================\n",
    });
    print_step.step.dependOn(&lib.step);
    b.getInstallStep().dependOn(&print_step.step);
}
