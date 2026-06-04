const builtin = @import("builtin");

const std = @import("std");
const fenv = std.math.fenv;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&feclearexcept, "feclearexcept");
        symbol(&fegetexceptflag, "fegetexceptflag");
        symbol(&feraiseexcept, "feraiseexcept");
        symbol(&fesetexceptflag, "fesetexceptflag");
        symbol(&fetestexcept, "fetestexcept");
        symbol(&fegetround, "fegetround");
        symbol(&fesetround, "fesetround");
        symbol(&fegetenv, "fegetenv");
        symbol(&feholdexcept, "feholdexcept");
        symbol(&fesetenv, "fesetenv");
        symbol(&feupdateenv, "feupdateenv");
    }
}

fn feclearexcept(mask: c_int) callconv(.c) c_int {
    fenv.clearExcept(@truncate(@as(c_uint, @bitCast(mask))));
    return 0;
}
fn fegetexceptflag(fexcept_t: ?*fenv.exception_t, mask: c_int) callconv(.c) c_int {
    if (fexcept_t) |f_ptr| {
        if (@intFromPtr(f_ptr) == std.math.maxInt(usize)) {
            return -1;
        } else {
            // _ = mask;
            f_ptr.* = fenv.getExceptFlag(@truncate(@as(c_uint, @bitCast(mask))));
        }
    }
    return 0;
}
fn feraiseexcept(excepts: c_int) callconv(.c) c_int {
    fenv.raiseExcept(@truncate(@as(c_uint, @bitCast(excepts))));
    return 0;
}
fn fesetexceptflag(fexcept_t: ?*const fenv.exception_t, mask: c_int) callconv(.c) c_int {
    if (fexcept_t) |f_ptr| {
        if (@intFromPtr(f_ptr) == std.math.maxInt(usize)) {
            return -1;
        } else {
            fenv.setExceptFlag(f_ptr.*, @truncate(@as(c_uint, @bitCast(mask))));
        }
    }
    return 0;
}
fn fetestexcept(mask: c_int) callconv(.c) c_int {
    if (mask == -1) return 0;
    return @intCast(fenv.testExcept(@truncate(@as(c_uint, @bitCast(mask)))));
}

fn fegetround() callconv(.c) c_int {
    return @intCast(fenv.getRound());
}
fn fesetround(mode: c_int) callconv(.c) c_int {
    const m: fenv.exception_t = @truncate(@as(c_uint, @bitCast(mode)));
    if (m & ~(fenv.RoundingMode.downward | fenv.RoundingMode.upward | fenv.RoundingMode.toward_zero) != 0) return -1;
    fenv.setRound(m);
    return 0;
}

fn fegetenv(fenv_t: ?*fenv.Env) callconv(.c) c_int {
    if (fenv_t == null) {
        return 0;
    }

    if (@intFromPtr(fenv_t.?) == std.math.maxInt(usize)) {
        return 0;
    }
    const ptr: *align(1) fenv.Env = @ptrCast(fenv_t.?);
    ptr.* = fenv.getEnv();
    return 0;
}
fn feholdexcept(fenv_t: ?*fenv.Env) callconv(.c) c_int {
    if (fenv_t == null) {
        return 0;
    }

    if (@intFromPtr(fenv_t.?) == std.math.maxInt(usize)) {
        return 0;
    }
    const ptr: *align(1) fenv.Env = @ptrCast(fenv_t.?);
    ptr.* = fenv.holdExcept();
    return 0;
}
fn fesetenv(fenv_t: ?*const anyopaque) callconv(.c) c_int {
    if (fenv_t == null) {
        fenv.setEnv(.{});
        return 0;
    }

    if (@intFromPtr(fenv_t.?) == std.math.maxInt(usize)) {
        fenv.setEnv(.{});
        return 0;
    }
    const ptr: *align(1) const fenv.Env = @ptrCast(fenv_t.?);
    fenv.setEnv(ptr.*);
    return 0;
}
fn feupdateenv(fenv_t: ?*const anyopaque) callconv(.c) c_int {
    if (fenv_t == null) {
        fenv.updateEnv(.{});
        return 0;
    }

    if (@intFromPtr(fenv_t.?) == std.math.maxInt(usize)) {
        fenv.updateEnv(.{});
        return 0;
    }
    const ptr: *align(1) const fenv.Env = @ptrCast(fenv_t.?);
    fenv.updateEnv(ptr.*);
    return 0;
}
