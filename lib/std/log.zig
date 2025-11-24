//! std.log is a standardized interface for logging which allows for the logging
//! of programs and libraries using this interface to be formatted and filtered
//! by the implementer of the `std.options.logFn` function.
//!
//! Each log message has an associated scope enum, which can be used to give
//! context to the logging. The logging functions in std.log implicitly use a
//! scope of .default.
//!
//! A logging namespace using a custom scope can be created using the
//! std.log.scoped function, passing the scope as an argument; the logging
//! functions in the resulting struct use the provided scope parameter.
//! For example, a library called 'libfoo' might use
//! `const log = std.log.scoped(.libfoo);` to use .libfoo as the scope of its
//! log messages.
//!
//! For an example implementation of the `logFn` function, see `defaultLog`,
//! which is the default implementation. It outputs to stderr, using color if
//! the detected `std.Io.tty.Config` supports it. Its output looks like this:
//! ```
//! error: this is an error
//! error(scope): this is an error with a non-default scope
//! warning: this is a warning
//! info: this is an informative message
//! debug: this is a debugging message
//! ```

const std = @import("std.zig");
const assert = std.debug.assert;
const builtin = @import("builtin");
const SourceLocation = std.builtin.SourceLocation;
const SpanUserdata = std.options.SpanUserdata;

pub const Level = enum {
    /// Error: something has gone wrong. This might be recoverable or might
    /// be followed by the program exiting.
    err,
    /// Warning: it is uncertain if something has gone wrong or not, but the
    /// circumstances would be worth investigating.
    warn,
    /// Info: general messages about the state of the program.
    info,
    /// Debug: messages only useful for debugging.
    debug,

    /// Returns a string literal of the given level in full text form.
    pub fn asText(comptime self: Level) []const u8 {
        return switch (self) {
            .err => "error",
            .warn => "warning",
            .info => "info",
            .debug => "debug",
        };
    }
};

/// The default log level is based on build mode.
pub const default_level: Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
};

pub const ScopeLevel = struct {
    scope: @EnumLiteral(),
    level: Level,
};

fn log(
    comptime level: Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (comptime !logEnabled(level, scope)) return;

    std.options.logFn(level, scope, format, args);
}

/// Determine if a specific log message level and scope combination are enabled for logging.
pub fn logEnabled(comptime level: Level, comptime scope: @EnumLiteral()) bool {
    inline for (std.options.log_scope_levels) |scope_level| {
        if (scope_level.scope == scope) return @intFromEnum(level) <= @intFromEnum(scope_level.level);
    }
    return @intFromEnum(level) <= @intFromEnum(std.options.log_level);
}

/// The default implementation for the log function. Custom log functions may
/// forward log messages to this function.
///
/// Uses a 64-byte buffer for formatted printing which is flushed before this
/// function returns.
pub fn defaultLog(
    comptime level: Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    var buffer: [64]u8 = undefined;
    const stderr, const ttyconf = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();
    ttyconf.setColor(stderr, switch (level) {
        .err => .red,
        .warn => .yellow,
        .info => .green,
        .debug => .magenta,
    }) catch {};
    ttyconf.setColor(stderr, .bold) catch {};
    stderr.writeAll(level.asText()) catch return;
    ttyconf.setColor(stderr, .reset) catch {};
    ttyconf.setColor(stderr, .dim) catch {};
    ttyconf.setColor(stderr, .bold) catch {};
    if (scope != .default) {
        stderr.print("({s})", .{@tagName(scope)}) catch return;
    }
    stderr.writeAll(": ") catch return;
    ttyconf.setColor(stderr, .reset) catch {};
    stderr.print(format ++ "\n", args) catch return;
}

fn trace(
    comptime level: Level,
    comptime scope: @EnumLiteral(),
    comptime src: SourceLocation,
    comptime event: SpanEvent,
    executor: Executor,
    span_: *Span,
) void {
    if (comptime !logEnabled(level, scope)) return;
    std.options.traceFn(level, scope, src, event, executor, @ptrCast(span_));
}

pub fn defaultTrace(
    comptime level: Level,
    comptime scope: @EnumLiteral(),
    comptime src: SourceLocation,
    comptime event: SpanEvent,
    executor: Executor,
    any_span: *anyopaque,
) void {
    _ = level;
    _ = scope;
    _ = src;
    _ = event;
    _ = executor;
    _ = any_span;
}

pub threadlocal var current_executor: Executor = .none;
pub threadlocal var current_span: Span = .none;

/// An executor can be a thread, fiber, or whatever the std.Io implementation
/// decides it is. Internally it is represented by a monotonically increasing
/// integer, but that is an implementation detail, and should not be relied
/// upon.
pub const Executor = enum(u64) {
    none = std.math.maxInt(u64),
    _,

    var next_id: std.atomic.Value(u64) = .init(0);

    pub fn create() Executor {
        return @enumFromInt(next_id.fetchAdd(1, .monotonic));
    }

    /// Link the work happening on the current thread to the span that
    /// originally created it.
    pub fn link(self: Executor, span_: *Span) void {
        if (span_.id == .none) return;
        span_.vtable.linkFn(span_, self);
    }

    /// Unlink the work happening on the current thread from the span that
    /// originally created it.
    pub fn unlink(self: Executor, span_: *Span) void {
        if (span_.id == .none) return;
        span_.vtable.unlinkFn(span_, self);
    }
};

/// An code execution span.
pub const Span = struct {
    id: SpanId,
    vtable: *const VTable,
    userdata: SpanUserdata,

    pub const none: Span = .{
        .id = .none,
        .vtable = undefined,
        .userdata = undefined,
    };

    pub const VTable = struct {
        suspendFn: *const fn (self: *Span) Span,
        resumeFn: *const fn (self: Span) void,
        linkFn: *const fn (self: *Span, executor: Executor) void,
        unlinkFn: *const fn (self: *Span, executor: Executor) void,
    };

    /// Marks the span as suspended on the current thread. This method assumes
    /// ownership of the returned span -- an implementor of `std.Io` should hold
    /// on to it until it `resume`s.
    pub fn @"suspend"(self: *Span) Span {
        if (self.id == .none) return none;
        return self.vtable.suspendFn(self);
    }

    /// Marks the span as resumed on the current thread. Takes ownership of the
    /// span, placing it in `current_thread` as the active span.
    pub fn @"resume"(self: Span) void {
        if (self.id == .none) return;
        self.vtable.resumeFn(self);
    }
};

/// Internally this is represented by a monotonically increasing integer, but
/// that is an implementation detail, and should not be relied upon.
pub const SpanId = enum(u64) {
    none = std.math.maxInt(u64),
    _,

    var next_id: std.atomic.Value(u64) = .init(0);

    pub fn createNext() SpanId {
        return @enumFromInt(next_id.fetchAdd(1, .monotonic));
    }
};

/// A tracing span that is generic over the log level, scope, and source location.
/// When the scope or level has been disabled via `std.Options`, this type becomes
/// zero sized, and all methods become no-ops, allowing the traces to be optimized
/// away by the compiler.
///
/// ```zig
/// const span = log.span(.info, @src());
/// defer span.end();
/// ```
///
/// When multithreading, to properly track spans across threads, you must create an
/// executor and link it to this span, the unlink when the thread is no longer handling
/// the span's work.
///
/// ```zig
/// std.thread.Spawn(.{}, struct {
///     fn myFn(span: *AnySpan) void {
///        const executor = std.log.Executor.create();
///        executor.link(span);
///        defer executor.unlink(span);
///
///       // new spans on this thread are now linked to the original
///     }
/// }.myFn, .{ &span.any });
/// ```
///
/// When dealing with suspendable fibers, you must suspend and resume the span
/// from the thread that is executing the fiber.
pub fn ScopedSpan(comptime level: Level, comptime scope: @EnumLiteral(), comptime src: std.builtin.SourceLocation) type {
    return if (!logEnabled(level, scope)) struct {
        const Self = @This();

        pub fn begin() Self {
            return .{};
        }
        pub fn end(_: *Self) void {}
    } else struct {
        const Self = @This();

        id: SpanId,
        prev: Span,

        /// Begins a new span on the current thread.
        pub fn begin() Self {
            const id: SpanId = .createNext();
            const prev = current_span;
            current_span = .{
                .id = id,
                .vtable = &.{
                    .suspendFn = @"suspend",
                    .resumeFn = @"resume",
                    .linkFn = link,
                    .unlinkFn = unlink,
                },
                .userdata = undefined,
            };
            trace(level, scope, src, .begin, current_executor, &current_span);
            return .{ .id = id, .prev = prev };
        }

        pub fn end(self: *Self) void {
            // Swap the previous span, that we stored from begin,
            assert(current_span.id != .none);
            assert(current_span.id == self.id);
            trace(level, scope, src, .end, current_executor, &current_span);
            current_span = self.prev;
            self.* = undefined;
        }

        fn @"suspend"(span_: *Span) Span {
            assert(span_.id != .none);
            assert(current_span.id != .none);
            assert(current_span.id == span_.id);
            trace(level, scope, src, .@"suspend", current_executor, &current_span);
            const suspended = span_.*;
            current_span = .none;
            return suspended;
        }

        fn @"resume"(span_: Span) void {
            assert(span_.id != .none);
            assert(current_span.id == .none);
            current_span = span_;
            trace(level, scope, src, .@"resume", current_executor, &current_span);
        }

        fn link(span_: *Span, executor: Executor) void {
            assert(executor != .none);
            assert(span_.id != .none);
            assert(current_executor == .none);
            assert(current_span.id == .none);
            current_executor = executor;
            trace(level, scope, src, .link, current_executor, span_);
        }

        fn unlink(span_: *Span, executor: Executor) void {
            assert(current_executor != .none);
            assert(current_executor == executor);
            assert(current_span.id == .none);
            trace(level, scope, src, .unlink, current_executor, span_);
            current_executor = .none;
        }
    };
}

pub const SpanEvent = enum {
    /// An executor has begun work on this span.
    begin,
    /// An executor has completed work on this span.
    end,
    /// An executor has suspended work on this span.
    @"suspend",
    /// An executor has resumed work on this span.
    @"resume",
    /// An executor has started work requested within the span.
    link,
    /// An executor has stopped work requested within the span.
    unlink,
};

/// Returns a scoped logging namespace that logs all messages using the scope
/// provided here.
pub fn scoped(comptime scope: @EnumLiteral()) type {
    return struct {
        /// Log an error message. This log level is intended to be used
        /// when something has gone wrong. This might be recoverable or might
        /// be followed by the program exiting.
        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            @branchHint(.cold);
            log(.err, scope, format, args);
        }

        /// Log a warning message. This log level is intended to be used if
        /// it is uncertain whether something has gone wrong or not, but the
        /// circumstances would be worth investigating.
        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.warn, scope, format, args);
        }

        /// Log an info message. This log level is intended to be used for
        /// general messages about the state of the program.
        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.info, scope, format, args);
        }

        /// Log a debug message. This log level is intended to be used for
        /// messages which are only useful for debugging.
        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.debug, scope, format, args);
        }

        /// Initialize a new tracing span. The span must be explicitly begun
        /// and ended after initialization.
        pub fn span(
            comptime level: Level,
            comptime src: SourceLocation,
        ) ScopedSpan(level, scope, src) {
            return .begin();
        }
    };
}

pub const default_log_scope = .default;

/// The default scoped logging namespace.
pub const default = scoped(default_log_scope);

/// Log an error message using the default scope. This log level is intended to
/// be used when something has gone wrong. This might be recoverable or might
/// be followed by the program exiting.
pub const err = default.err;

/// Log a warning message using the default scope. This log level is intended
/// to be used if it is uncertain whether something has gone wrong or not, but
/// the circumstances would be worth investigating.
pub const warn = default.warn;

/// Log an info message using the default scope. This log level is intended to
/// be used for general messages about the state of the program.
pub const info = default.info;

/// Log a debug message using the default scope. This log level is intended to
/// be used for messages which are only useful for debugging.
pub const debug = default.debug;

/// Initialize a new tracing span using the default scope. The span must be
/// explicitly begun and ended after initialization.
pub const span = default.span;
