const builtin = @import("builtin");
const std = @import("std");

inline fn testBit(cfg: u32, bitToTest: i32) bool {
    return cfg & (1 << bitToTest) != 0;
}

inline fn addFeature(cpu: *std.Target.Cpu, feature: std.Target.loongarch.Feature) void {
    cpu.features.addFeature(@intFromEnum(feature));
}

pub fn detectNativeCpuAndFeatures(
    arch: std.Target.Cpu.Arch,
    os: std.Target.Os,
    query: std.Target.Query,
) ?std.Target.Cpu {
    _ = os;
    _ = query;

    // Clearly this code could do better in the future by actually querying specific CPU features
    // with the cpucfg instruction like on x86. But with the small number of well-known LoongArch
    // models that exist at the moment, simply checking the PRID is plenty.
    var cpu: std.Target.Cpu = .{
        .arch = arch,
        .model = switch (cpucfg(0) & 0xf000) {
            else => return null,
            0xc000 => &std.Target.loongarch.cpu.la464,
            0xd000 => &std.Target.loongarch.cpu.la664,
        },
        .features = .empty,
    };

    cpu.features.addFeatureSet(cpu.model.features);
    cpu.features.populateDependencies(cpu.arch.allFeaturesList());

    const cfg1 = cpucfg(1);
    const cfg2 = cpucfg(2);
    const cfg3 = cpucfg(3);

    if (testBit(cfg1, 20)) addFeature(&cpu, std.Target.loongarch.Feature.ual);

    const hasFpu = testBit(cfg2, 0);
    if (hasFpu) {
        if (testBit(cfg2,1)) addFeature(&cpu, std.Target.loongarch.Feature.f);
        if (testBit(cfg2,2)) addFeature(&cpu, std.Target.loongarch.Feature.d);
    }

    if (testBit(cfg2, 6)) addFeature(&cpu, std.Target.loongarch.Feature.lsx);
    if (testBit(cfg2, 7)) addFeature(&cpu, std.Target.loongarch.Feature.lasx);
    if (testBit(cfg2, 10)) addFeature(&cpu, std.Target.loongarch.Feature.lvz);

    if (testBit(cfg2, 25)) addFeature(&cpu, std.Target.loongarch.Feature.frecipe);
    if (testBit(cfg2, 26)) addFeature(&cpu, std.Target.loongarch.Feature.div32);
    if (testBit(cfg2, 27)) addFeature(&cpu, std.Target.loongarch.Feature.lam_bh);
    if (testBit(cfg2, 28)) addFeature(&cpu, std.Target.loongarch.Feature.lamcas);
    if (testBit(cfg2, 30)) addFeature(&cpu, std.Target.loongarch.Feature.scq);

    if (testBit(cfg3, 23)) addFeature(&cpu, std.Target.loongarch.Feature.ld_seq_sa);

    return cpu;
}

/// This is a workaround for the C backend until zig has the ability to put
/// C code in inline assembly.
extern fn zig_loongarch_cpucfg(word: u32, result: *u32) callconv(.c) void;

fn cpucfg(word: u32) u32 {
    var result: u32 = undefined;

    if (builtin.zig_backend == .stage2_c) {
        zig_loongarch_cpucfg(word, &result);
    } else {
        asm ("cpucfg %[result], %[word]"
            : [result] "=r" (result),
            : [word] "r" (word),
        );
    }

    return result;
}
