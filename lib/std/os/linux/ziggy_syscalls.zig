///! Syscalls that are more ziggy.
const builtin = @import("builtin");
const linux = @import("../linux.zig");
const errno = @import("errno.zig");

pub const ErrnoError = errno.Error;

pub const errorFromSyscall = linux.errorFromSyscall;

const EXECVEAT = linux.EXECVEAT;
const pid_t = linux.pid_t;
const fd_t = linux.fd_t;
const wd_t = linux.wd_t;
const SIG = linux.SIG;
const timespec = linux.timespec;
const clockid_t = linux.clockid_t;
const mode_t = linux.mode_t;
const MOVE_MOUNT = linux.MOVE_MOUNT;
const MOUNT_ATTR = linux.MOUNT_ATTR;
const FSOPEN = linux.FSOPEN;
const FSPICK = linux.FSPICK;
const FSCONFIG_CMD = linux.FSCONFIG_CMD;
const FSMOUNT = linux.FSMOUNT;
const PROT = linux.PROT;
const MAP = linux.MAP;
const sigset_t = linux.sigset_t;
const iovec = linux.iovec;
const iovec_const = linux.iovec_const;
const O = linux.O;
const uid_t = linux.uid_t;
const gid_t = linux.gid_t;
const rusage = linux.rusage;
const P = linux.P;
const siginfo_t = linux.siginfo_t;
const itimerspec = linux.itimerspec;
const timeval = linux.timeval;
const timezone = linux.timezone;
const Sigaction = linux.Sigaction;
const sockaddr = linux.sockaddr;
const socklen_t = linux.socklen_t;
const msghdr = linux.msghdr;
const msghdr_const = linux.msghdr_const;
const mmsghdr = linux.mmsghdr;
const STATX = linux.STATX;
const Statx = linux.Statx;
const SCHED = linux.SCHED;
const sched_param = linux.sched_param;
const sched_attr = linux.sched_attr;
const cpu_set_t = linux.cpu_set_t;
const epoll_event = linux.epoll_event;
const timerfd_clockid_t = linux.timerfd_clockid_t;
const TFD = linux.TFD;
const cap_user_header_t = linux.cap_user_header_t;
const cap_user_data_t = linux.cap_user_data_t;
const stack_t = linux.stack_t;
const utsname = linux.utsname;
const io_uring_params = linux.io_uring_params;
const IORING_REGISTER = linux.IORING_REGISTER;
const termios = linux.termios;
const TCSA = linux.TCSA;
const BPF = linux.BPF;
const rlimit_resource = linux.rlimit_resource;
const rlimit = linux.rlimit;
const perf_event_attr = linux.perf_event_attr;
const cache_stat_range = linux.cache_stat_range;
const cache_stat = linux.cache_stat;
const Sysinfo = linux.Sysinfo;
const FUTEX_OP = linux.FUTEX_OP;
const futex_param4 = linux.futex_param4;
const FUTEX2_FLAGS_WAITV = linux.FUTEX2_FLAGS_WAITV;
const FUTEX2_FLAGS = linux.FUTEX2_FLAGS;
const FUTEX2_FLAGS_REQUEUE = linux.FUTEX2_FLAGS_REQUEUE;
const fanotify = linux.fanotify;
const MREMAP = linux.MREMAP;
const MLOCK = linux.MLOCK;
const MCL = linux.MCL;
const nfds_t = linux.nfds_t;
const kernel_rwf = linux.kernel_rwf;
const RENAME = linux.RENAME;
const CLOSE_RANGE = linux.CLOSE_RANGE;
const LINUX_REBOOT = linux.LINUX_REBOOT;
const TIMER = linux.TIMER;
const ITIMER = linux.ITIMER;

pub fn dup(old: fd_t) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.dup(old)));
}

pub fn dup2(old: fd_t, new: fd_t) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.dup2(old, new)));
}

pub fn dup3(old: fd_t, new: fd_t, flags: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.dup3(old, new, flags)));
}

pub fn chdir(path: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.chdir(path));
}

pub fn fchdir(fd: fd_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.fchdir(fd));
}

pub fn chroot(path: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.chroot(path));
}

pub fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) ErrnoError!noreturn {
    try errorFromSyscall(linux.execve(path, argv, envp));
    unreachable;
}

pub fn execveat(dirfd: fd_t, path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8, flags: EXECVEAT) ErrnoError!noreturn {
    try errorFromSyscall(linux.execveat(dirfd, path, argv, envp, flags));
    unreachable;
}

pub fn fork() ErrnoError!?pid_t {
    const pid = pidFromUsize(try errorFromSyscall(linux.fork()));
    if (pid == 0) {
        // Child receives 0.
        return null;
    } else {
        // Parent receives the child's pid.
        return pid;
    }
}

/// This must be inline, and inline call the syscall function, because if the
/// child does a return it will clobber the parent's stack.
/// It is advised to avoid this function and use clone instead, because
/// the compiler is not aware of how vfork affects control flow and you may
/// see different results in optimized builds.
pub inline fn vfork() usize {
    return @call(.always_inline, linux.syscall0, .{.vfork});
}

/// See also `clone` (from the arch-specific include)
pub fn clone2(flags: u32, child_stack_ptr: usize) ErrnoError!usize {
    return errorFromSyscall(linux.clone2(flags, child_stack_ptr));
}

/// See also `clone` (from the arch-specific include)
pub fn clone5(flags: usize, child_stack_ptr: usize, parent_tid: *pid_t, child_tid: *pid_t, new_tls: usize) ErrnoError!usize {
    return errorFromSyscall(linux.clone5(flags, child_stack_ptr, parent_tid, child_tid, new_tls));
}

pub fn clone(
    func: *const fn (arg: usize) callconv(.c) u8,
    stack: usize,
    flags: u32,
    arg: usize,
    parent_tid: ?*pid_t,
    new_tls: usize,
    child_tid: ?*pid_t,
) ErrnoError!usize {
    return errorFromSyscall(linux.clone(func, stack, flags, arg, parent_tid, new_tls, child_tid));
}

pub fn futimens(fd: fd_t, times: ?*const [2]timespec) ErrnoError!void {
    _ = try errorFromSyscall(linux.futimens(fd, times));
}

pub fn utimensat(dirfd: fd_t, path: ?[*:0]const u8, times: ?*const [2]timespec, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.utimensat(dirfd, path, times, flags));
}

pub fn fallocate(fd: fd_t, mode: i32, offset: i64, length: i64) ErrnoError!void {
    _ = try errorFromSyscall(linux.fallocate(fd, mode, offset, length));
}

/// The futex v1 syscall, see also the newer the futex2_{wait,wakeup,requeue,waitv} syscalls.
///
/// The futex_op parameter is a sub-command and flags.  The sub-command
/// defines which of the subsequent paramters are relevant.
pub fn futex(uaddr: *const anyopaque, futex_op: FUTEX_OP, val: u32, val2timeout: futex_param4, uaddr2: ?*const anyopaque, val3: u32) ErrnoError!usize {
    return errorFromSyscall(linux.futex(uaddr, futex_op, val, val2timeout, uaddr2, val3));
}

/// Three-argument variation of the v1 futex call.  Only suitable for a
/// futex_op that ignores the remaining arguments (e.g., FUTEX_OP.WAKE).
pub fn futex_3arg(uaddr: *const anyopaque, futex_op: FUTEX_OP, val: u32) ErrnoError!usize {
    return errorFromSyscall(linux.futex_3arg(uaddr, futex_op, val));
}

/// Four-argument variation on the v1 futex call.  Only suitable for
/// futex_op that ignores the remaining arguments (e.g., FUTEX_OP.WAIT).
pub fn futex_4arg(uaddr: *const anyopaque, futex_op: FUTEX_OP, val: u32, timeout: ?*const timespec) ErrnoError!usize {
    return errorFromSyscall(linux.futex_4arg(uaddr, futex_op, val, timeout));
}

/// Given an array of `futex2_waitone`, wait on each uaddr.
/// The thread wakes if a futex_wake() is performed at any uaddr.
/// The syscall returns immediately if any futex has *uaddr != val.
/// timeout is an optional, absolute timeout value for the operation.
/// The `flags` argument is for future use and currently should be `.{}`.
/// Flags for private futexes, sizes, etc. should be set on the
/// individual flags of each `futex2_waitone`.
///
/// Returns the array index of one of the woken futexes.
/// No further information is provided: any number of other futexes may also
/// have been woken by the same event, and if more than one futex was woken,
/// the returned index may refer to any one of them.
/// (It is not necessaryily the futex with the smallest index, nor the one
/// most recently woken, nor...)
///
/// Requires at least kernel v5.16.
pub fn futex2_waitv(
    futexes: [*]const linux.futex2_waitone,
    /// Length of `futexes`.  Max of FUTEX2_WAITONE_MAX.
    nr_futexes: u32,
    flags: FUTEX2_FLAGS_WAITV,
    /// Optional absolute timeout.  Always 64-bit, even on 32-bit platforms.
    timeout: ?*const linux.kernel_timespec,
    /// Clock to be used for the timeout, realtime or monotonic.
    clockid: clockid_t,
) ErrnoError!usize {
    return errorFromSyscall(linux.futex2_waitv(futexes, nr_futexes, flags, timeout, clockid));
}

/// Wait on a single futex.
/// Identical to the futex v1 `FUTEX.FUTEX_WAIT_BITSET` op, except it is part of the
/// futex2 family of calls.
///
/// Requires at least kernel v6.7.
pub fn futex2_wait(
    /// Address of the futex to wait on.
    uaddr: *const anyopaque,
    /// Value of `uaddr`.
    val: usize,
    /// Bitmask to match against incoming wakeup masks.  Must not be zero.
    mask: usize,
    flags: FUTEX2_FLAGS,
    /// Optional absolute timeout.  Always 64-bit, even on 32-bit platforms.
    timeout: ?*const linux.kernel_timespec,
    /// Clock to be used for the timeout, realtime or monotonic.
    clockid: clockid_t,
) ErrnoError!usize {
    return errorFromSyscall(linux.futex2_wait(uaddr, val, mask, flags, timeout, clockid));
}

/// Wake (subset of) waiters on given futex.
/// Identical to the traditional `FUTEX.FUTEX_WAKE_BITSET` op, except it is part of the
/// futex2 family of calls.
///
/// Requires at least kernel v6.7.
pub fn futex2_wake(
    /// Futex to wake
    uaddr: *const anyopaque,
    /// Bitmask to match against waiters.
    mask: usize,
    /// Maximum number of waiters on the futex to wake.
    nr_wake: i32,
    flags: FUTEX2_FLAGS,
) ErrnoError!usize {
    return errorFromSyscall(linux.futex2_wake(uaddr, mask, nr_wake, flags));
}

/// Wake and/or requeue waiter(s) from one futex to another.
/// Identical to `FUTEX.CMP_REQUEUE`, except it is part of the futex2 family of calls.
///
/// Requires at least kernel v6.7.
pub fn futex2_requeue(
    /// The source and destination futexes.  Must be a 2-element array.
    waiters: [*]const linux.futex2_waitone,
    /// Currently unused.
    flags: FUTEX2_FLAGS_REQUEUE,
    /// Maximum number of waiters to wake on the source futex.
    nr_wake: i32,
    /// Maximum number of waiters to transfer to the destination futex.
    nr_requeue: i32,
) ErrnoError!usize {
    return errorFromSyscall(linux.futex2_requeue(waiters, flags, nr_wake, nr_requeue));
}

pub fn getcwd(buffer: []u8) ErrnoError![:0]u8 {
    const n_written = try errorFromSyscall(linux.getcwd(buffer.ptr, buffer.len));
    if (n_written == 0) {
        return buffer[0..0];
    } else {
        return buffer[0 .. n_written - 1]; // -1 for null byte.
    }
}

/// dirent_buffer is a buffer containing one or more dirent.
pub fn getdents(fd: fd_t, dirent_buffer: []u8) ErrnoError!usize {
    return errorFromSyscall(linux.getdents(fd, dirent_buffer.ptr, dirent_buffer.len));
}

/// dirent_buffer is a buffer containing one or more dirent64.
pub fn getdents64(fd: fd_t, dirent_buffer: []u8) ErrnoError!usize {
    return errorFromSyscall(linux.getdents64(fd, dirent_buffer.ptr, dirent_buffer.len));
}

pub fn inotify_init1(flags: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.inotify_init1(flags)));
}

pub fn inotify_add_watch(fd: fd_t, pathname: [*:0]const u8, mask: u32) ErrnoError!wd_t {
    return wdFromUsize(try errorFromSyscall(linux.inotify_add_watch(fd, pathname, mask)));
}

pub fn inotify_rm_watch(fd: fd_t, wd: wd_t) ErrnoError!usize {
    return errorFromSyscall(linux.inotify_rm_watch(fd, wd));
}

pub fn fanotify_init(flags: fanotify.InitFlags, event_f_flags: u32) ErrnoError!usize {
    return errorFromSyscall(linux.fanotify_init(flags, event_f_flags));
}

pub fn fanotify_mark(
    fd: fd_t,
    flags: fanotify.MarkFlags,
    mask: fanotify.MarkMask,
    dirfd: fd_t,
    pathname: ?[*:0]const u8,
) ErrnoError!usize {
    return errorFromSyscall(linux.fanotify_mark(fd, flags, mask, dirfd, pathname));
}

pub fn name_to_handle_at(
    dirfd: fd_t,
    pathname: [*:0]const u8,
    handle: *linux.file_handle,
    mount_id: *i32,
    flags: u32,
) ErrnoError!usize {
    return errorFromSyscall(linux.name_to_handle_at(dirfd, pathname, handle, mount_id, flags));
}

pub fn readlink(noalias path: [*:0]const u8, noalias buf_ptr: [*]u8, buf_len: usize) ErrnoError!usize {
    return errorFromSyscall(linux.readlink(path, buf_ptr, buf_len));
}

pub fn readlinkat(dirfd: fd_t, noalias path: [*:0]const u8, noalias buf_ptr: [*]u8, buf_len: usize) ErrnoError!usize {
    return errorFromSyscall(linux.readlinkat(dirfd, path, buf_ptr, buf_len));
}

pub fn mkdir(path: [*:0]const u8, mode: mode_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.mkdir(path, mode));
}

pub fn mkdirat(dirfd: fd_t, path: [*:0]const u8, mode: mode_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.mkdirat(dirfd, path, mode));
}

pub fn mknod(path: [*:0]const u8, mode: u32, dev: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.mknod(path, mode, dev));
}

pub fn mknodat(dirfd: fd_t, path: [*:0]const u8, mode: u32, dev: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.mknodat(dirfd, path, mode, dev));
}

pub fn mount(special: ?[*:0]const u8, dir: [*:0]const u8, fstype: ?[*:0]const u8, flags: u32, data: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.mount(special, dir, fstype, flags, data));
}

pub fn umount(special: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.umount(special));
}

pub fn umount2(special: [*:0]const u8, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.umount2(special, flags));
}

pub fn move_mount(from_dirfd: fd_t, from_path: [*:0]const u8, to_dirfd: fd_t, to_path: [*:0]const u8, flags: MOVE_MOUNT) ErrnoError!void {
    _ = try errorFromSyscall(linux.move_mount(from_dirfd, from_path, to_dirfd, to_path, flags));
}

pub fn mount_setattr(dirfd: fd_t, path: [*:0]const u8, flags: MOUNT_ATTR) ErrnoError!void {
    _ = try errorFromSyscall(linux.mount_setattr(dirfd, path, flags));
}

pub fn fsopen(fsname: [*:0]const u8, flags: FSOPEN) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.fsopen(fsname, flags)));
}

pub fn fsconfig(fd: fd_t, cmd: FSCONFIG_CMD, key: ?[*:0]const u8, value: ?[*:0]const u8, aux: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.fsconfig(fd, cmd, key, value, aux));
}

pub fn fsmount(fsfd: fd_t, flags: FSMOUNT, attr_flags: MOUNT_ATTR) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.fsmount(fsfd, flags, attr_flags)));
}

pub fn fspick(dirfd: fd_t, path: [*:0]const u8, flags: FSPICK) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.fspick(dirfd, path, flags)));
}

pub fn pivot_root(new_root: [*:0]const u8, put_old: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.pivot_root(new_root, put_old));
}

pub fn mmap(address: ?[*]u8, length: usize, prot: PROT, flags: MAP, fd: fd_t, offset: i64) ErrnoError![*]u8 {
    return @ptrFromInt(try errorFromSyscall(linux.mmap(address, length, prot, flags, fd, offset)));
}

pub fn munmap(address: [*]const u8, length: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.munmap(address, length));
}

pub fn mremap(old_addr: ?[*]const u8, old_len: usize, new_len: usize, flags: MREMAP, new_addr: ?[*]const u8) ErrnoError![*]u8 {
    return @ptrFromInt(errorFromSyscall(linux.mremap(old_addr, old_len, new_len, flags, new_addr)));
}

pub fn mprotect(address: [*]const u8, length: usize, protection: PROT) ErrnoError!void {
    _ = try errorFromSyscall(linux.mprotect(address, length, protection));
}

/// Can only be called on 64 bit systems.
pub fn mseal(address_range: []const u8, flags: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.mseal(address_range.ptr, address_range.len, flags));
}

pub fn msync(address_range: []const u8, flags: i32) ErrnoError!void {
    _ = try errorFromSyscall(linux.msync(address_range.ptr, address_range.len, flags));
}

pub fn mlock(address_range: []const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.mlock(address_range.ptr, address_range.len));
}

pub fn munlock(address_range: []const u8, length: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.munlock(address_range.ptr, address_range.len, length));
}

pub fn mlock2(address_range: []const u8, flags: MLOCK) ErrnoError!void {
    _ = try errorFromSyscall(linux.mlock2(address_range.ptr, address_range.len, flags));
}

pub fn mlockall(flags: MCL) ErrnoError!void {
    _ = try errorFromSyscall(linux.mlockall(flags));
}

pub fn munlockall() ErrnoError!void {
    _ = try errorFromSyscall(linux.munlockall());
}

pub fn poll(fds: []linux.pollfd, timeout: i32) ErrnoError!usize {
    return errorFromSyscall(linux.poll(fds.ptr, fds.len, timeout));
}

pub fn ppoll(fds: []linux.pollfd, timeout: ?*timespec, sigmask: ?*const sigset_t) ErrnoError!usize {
    return errorFromSyscall(linux.ppoll(fds.ptr, fds.len, timeout, sigmask));
}

pub fn read(fd: fd_t, buffer: []u8) ErrnoError!usize {
    return errorFromSyscall(linux.read(fd, buffer.ptr, buffer.len));
}

pub fn pread(fd: fd_t, buffer: []u8, offset: i64) ErrnoError!usize {
    return errorFromSyscall(linux.pread(fd, buffer.ptr, buffer.len, offset));
}

pub fn readv(fd: fd_t, iov: []const iovec) ErrnoError!usize {
    return errorFromSyscall(linux.readv(fd, iov.ptr, iov.len));
}

pub fn preadv(fd: fd_t, iov: []const iovec, offset: i64) ErrnoError!usize {
    return errorFromSyscall(linux.preadv(fd, iov.ptr, iov.len, offset));
}

pub fn preadv2(fd: fd_t, iov: []const iovec, offset: i64, flags: kernel_rwf) ErrnoError!usize {
    return errorFromSyscall(linux.preadv2(fd, iov.ptr, iov.len, offset, flags));
}

pub fn write(fd: fd_t, buffer: []const u8) ErrnoError!usize {
    return errorFromSyscall(linux.write(fd, buffer.ptr, buffer.len));
}

pub fn pwrite(fd: fd_t, buffer: []const u8, offset: i64) ErrnoError!usize {
    return errorFromSyscall(linux.pwrite(fd, buffer.ptr, buffer.len, offset));
}

pub fn writev(fd: fd_t, iov: []const iovec_const) ErrnoError!usize {
    return errorFromSyscall(linux.writev(fd, iov.ptr, iov.len));
}

pub fn pwritev(fd: fd_t, iov: []const iovec_const, offset: i64) ErrnoError!usize {
    return errorFromSyscall(linux.pwritev(fd, iov.ptr, iov.len, offset));
}

pub fn pwritev2(fd: fd_t, iov: []const iovec_const, offset: i64, flags: kernel_rwf) ErrnoError!usize {
    return errorFromSyscall(linux.pwritev2(fd, iov.ptr, iov.len, offset, flags));
}

pub fn rmdir(path: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.rmdir(path));
}

pub fn symlink(existing: [*:0]const u8, new: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.symlink(existing, new));
}

pub fn symlinkat(existing: [*:0]const u8, newfd: fd_t, newpath: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.symlinkat(existing, newfd, newpath));
}

pub fn access(path: [*:0]const u8, mode: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.access(path, mode));
}

pub fn faccessat(dirfd: fd_t, path: [*:0]const u8, mode: u32, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.faccessat(dirfd, path, mode, flags));
}

pub fn acct(path: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.acct(path));
}

pub fn pipe() ErrnoError![2]fd_t {
    var fds: [2]fd_t = undefined;
    return fdFromUsize(try errorFromSyscall(linux.pipe(&fds)));
}

pub fn pipe2(flags: O) ErrnoError![2]fd_t {
    var fds: [2]fd_t = undefined;
    return fdFromUsize(try errorFromSyscall(linux.pipe2(&fds, flags)));
}

pub fn ftruncate(fd: fd_t, length: i64) ErrnoError!void {
    _ = try errorFromSyscall(linux.ftruncate(fd, length));
}

pub fn rename(old: [*:0]const u8, new: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.rename(old, new));
}

pub fn renameat(oldfd: fd_t, oldpath: [*:0]const u8, newfd: fd_t, newpath: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.renameat(oldfd, oldpath, newfd, newpath));
}

pub fn renameat2(oldfd: fd_t, oldpath: [*:0]const u8, newfd: fd_t, newpath: [*:0]const u8, flags: RENAME) ErrnoError!void {
    _ = try errorFromSyscall(linux.renameat2(oldfd, oldpath, newfd, newpath, flags));
}

pub fn open(path: [*:0]const u8, flags: O, perm: mode_t) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.open(path, flags, perm)));
}

pub fn create(path: [*:0]const u8, perm: mode_t) ErrnoError!fd_t {
    return fdFromUsize(errorFromSyscall(linux.create(path, perm)));
}

pub fn openat(dirfd: fd_t, path: [*:0]const u8, flags: O, mode: mode_t) ErrnoError!fd_t {
    return fdFromUsize(errorFromSyscall(linux.openat(dirfd, path, flags, mode)));
}

pub fn close(fd: fd_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.close(fd));
}

pub fn close_range(first: fd_t, last: fd_t, flags: CLOSE_RANGE) ErrnoError!void {
    _ = try errorFromSyscall(linux.close_range(first, last, flags));
}

pub fn fchmod(fd: fd_t, mode: mode_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.fchmod(fd, mode));
}

pub fn chmod(path: [*:0]const u8, mode: mode_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.chmod(path, mode));
}

pub fn fchown(fd: fd_t, owner: uid_t, group: gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.fchown(fd, owner, group));
}

pub fn fchownat(fd: fd_t, path: [*:0]const u8, owner: uid_t, group: gid_t, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.fchownat(fd, path, owner, group, flags));
}

pub fn chown(path: [*:0]const u8, owner: uid_t, group: gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.chown(path, owner, group));
}

pub fn lchown(path: [*:0]const u8, owner: uid_t, group: gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.lchown(path, owner, group));
}

pub fn fchmodat(fd: fd_t, path: [*:0]const u8, mode: mode_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.fchmodat(fd, path, mode));
}

pub fn fchmodat2(fd: fd_t, path: [*:0]const u8, mode: mode_t, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.fchmodat2(fd, path, mode, flags));
}

/// Can only be called on 32 bit systems. For 64 bit see `lseek`.
pub fn llseek(fd: fd_t, offset: u64, result: ?*u64, whence: usize) ErrnoError!usize {
    return errorFromSyscall(linux.llseek(fd, offset, result, whence));
}

/// Can only be called on 64 bit systems. For 32 bit see `llseek`.
pub fn lseek(fd: fd_t, offset: i64, whence: usize) ErrnoError!usize {
    return errorFromSyscall(linux.lseek(fd, offset, whence));
}

pub fn exit(status: i32) noreturn {
    linux.exit(status);
}

pub fn exit_group(status: i32) noreturn {
    linux.exit_group(status);
}

pub fn reboot(magic: LINUX_REBOOT.MAGIC1, magic2: LINUX_REBOOT.MAGIC2, cmd: LINUX_REBOOT.CMD, arg: ?*const anyopaque) ErrnoError!void { // May return void or not return at all, depending on the command
    _ = try errorFromSyscall(linux.reboot(magic, magic2, cmd, arg));
}

pub fn getrandom(buffer: []u8, flags: u32) ErrnoError!usize {
    return errorFromSyscall(linux.getrandom(buffer.ptr, buffer.len, flags));
}

pub fn kill(pid: pid_t, sig: SIG) ErrnoError!void {
    _ = try errorFromSyscall(linux.kill(pid, sig));
}

pub fn tkill(tid: pid_t, sig: SIG) ErrnoError!void {
    _ = try errorFromSyscall(linux.tkill(tid, sig));
}

pub fn tgkill(tgid: pid_t, tid: pid_t, sig: SIG) ErrnoError!void {
    _ = try errorFromSyscall(linux.tgkill(tgid, tid, sig));
}

pub fn link(oldpath: [*:0]const u8, newpath: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.link(oldpath, newpath));
}

pub fn linkat(oldfd: fd_t, oldpath: [*:0]const u8, newfd: fd_t, newpath: [*:0]const u8, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.linkat(oldfd, oldpath, newfd, newpath, flags));
}

pub fn unlink(path: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.unlink(path));
}

pub fn unlinkat(dirfd: fd_t, path: [*:0]const u8, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.unlinkat(dirfd, path, flags));
}

pub fn waitpid(pid: pid_t, status: *u32, flags: u32) ErrnoError!usize {
    return errorFromSyscall(linux.waitpid(pid, status, flags));
}

pub fn wait4(pid: pid_t, status: *u32, flags: u32, usage: ?*rusage) ErrnoError!usize {
    return errorFromSyscall(linux.wait4(pid, status, flags, usage));
}

pub fn waitid(id_type: P, id: i32, infop: *siginfo_t, flags: u32, usage: ?*rusage) ErrnoError!usize {
    return errorFromSyscall(linux.waitid(id_type, id, infop, flags, usage));
}

pub fn fcntl(fd: fd_t, cmd: i32, arg: usize) ErrnoError!usize {
    return errorFromSyscall(linux.fcntl(fd, cmd, arg));
}

pub fn flock(fd: fd_t, operation: i32) ErrnoError!void {
    _ = try errorFromSyscall(linux.flock(fd, operation));
}

pub fn clock_gettime(clockid: clockid_t, tp: *timespec) ErrnoError!void {
    _ = try errorFromSyscall(linux.clock_gettime(clockid, tp));
}

pub fn clock_getres(clockid: clockid_t, tp: *timespec) ErrnoError!void {
    _ = try errorFromSyscall(linux.clock_getres(clockid, tp));
}

pub fn clock_settime(clockid: clockid_t, tp: *const timespec) ErrnoError!void {
    _ = try errorFromSyscall(linux.clock_settime(clockid, tp));
}

pub fn clock_nanosleep(clockid: clockid_t, flags: TIMER, request: *const timespec, remain: ?*timespec) ErrnoError!void {
    _ = try errorFromSyscall(linux.clock_nanosleep(clockid, flags, request, remain));
}

pub fn gettimeofday(tv: ?*timeval, tz: ?*timezone) ErrnoError!void {
    _ = try errorFromSyscall(linux.gettimeofday(tv, tz));
}

pub fn settimeofday(tv: *const timeval, tz: *const timezone) ErrnoError!void {
    _ = try errorFromSyscall(linux.settimeofday(tv, tz));
}

pub fn nanosleep(req: *const timespec, rem: ?*timespec) ErrnoError!void {
    _ = try errorFromSyscall(linux.nanosleep(req, rem));
}

pub fn pause() ErrnoError!void {
    _ = try errorFromSyscall(linux.pause());
}

pub fn setuid(uid: uid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setuid(uid));
}

pub fn setgid(gid: gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setgid(gid));
}

pub fn setreuid(ruid: uid_t, euid: uid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setreuid(ruid, euid));
}

pub fn setregid(rgid: gid_t, egid: gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setregid(rgid, egid));
}

pub fn getuid() uid_t {
    return linux.getuid();
}

pub fn getgid() gid_t {
    return linux.getgid();
}

pub fn geteuid() uid_t {
    return linux.geteuid();
}

pub fn getegid() gid_t {
    return linux.getegid();
}

pub fn seteuid(euid: uid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.seteuid(euid));
}

pub fn setegid(egid: gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setegid(egid));
}

pub fn getresuid(ruid: *uid_t, euid: *uid_t, suid: *uid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.getresuid(ruid, euid, suid));
}

pub fn getresgid(rgid: *gid_t, egid: *gid_t, sgid: *gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.getresgid(rgid, egid, sgid));
}

pub fn setresuid(ruid: uid_t, euid: uid_t, suid: uid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setresuid(ruid, euid, suid));
}

pub fn setresgid(rgid: gid_t, egid: gid_t, sgid: gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setresgid(rgid, egid, sgid));
}

pub fn setpgid(pid: pid_t, pgid: pid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setpgid(pid, pgid));
}

pub fn getpgid(pid: pid_t) ErrnoError!gid_t {
    return @as(gid_t, @intCast(try errorFromSyscall(linux.getpgid(pid))));
}

pub fn getgroups(buffer: []gid_t) ErrnoError!usize {
    return errorFromSyscall(linux.getgroups(buffer.len, buffer.ptr));
}

pub fn setgroups(groups: []const gid_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setgroups(groups.size, groups.ptr));
}

pub fn setsid() ErrnoError!usize {
    return @as(gid_t, @intCast(try errorFromSyscall(linux.setsid())));
}

pub fn getsid(pid: pid_t) ErrnoError!pid_t {
    return @as(gid_t, @intCast(try errorFromSyscall(linux.getsid(pid))));
}

pub fn getpid() pid_t {
    return linux.getpid();
}

pub fn getppid() pid_t {
    return linux.getppid();
}

pub fn gettid() pid_t {
    return linux.gettid();
}

pub fn sigprocmask(flags: u32, noalias set: ?*const sigset_t, noalias oldset: ?*sigset_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.sigprocmask(flags, set, oldset));
}

pub fn sigaction(sig: SIG, noalias act: ?*const Sigaction, noalias oact: ?*Sigaction) ErrnoError!void {
    _ = try errorFromSyscall(linux.sigaction(sig, act, oact));
}

/// Zig's SIGRTMIN, but is a function for compatibility with glibc
pub fn sigrtmin() u8 {
    return linux.sigrtmin();
}

/// Zig's SIGRTMAX, but is a function for compatibility with glibc
pub fn sigrtmax() u8 {
    return linux.sigrtmax();
}

/// Zig's version of sigemptyset.  Returns initialized sigset_t.
pub fn sigemptyset() sigset_t {
    return linux.sigemptyset();
}

/// Zig's version of sigfillset.  Returns initalized sigset_t.
pub fn sigfillset() sigset_t {
    return linux.sigfillset();
}

pub fn sigaddset(set: *sigset_t, sig: SIG) void {
    linux.sigaddset(set, sig);
}

pub fn sigdelset(set: *sigset_t, sig: SIG) void {
    linux.sigdelset(set, sig);
}

pub fn sigismember(set: *const sigset_t, sig: SIG) bool {
    return linux.sigismember(set, sig);
}

pub fn getsockname(fd: fd_t, noalias addr: *sockaddr, noalias len: *socklen_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.getsockname(fd, addr, len));
}

pub fn getpeername(fd: fd_t, noalias addr: *sockaddr, noalias len: *socklen_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.getpeername(fd, addr, len));
}

pub fn socket(domain: u32, socket_type: u32, protocol: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.socket(domain, socket_type, protocol)));
}

pub fn setsockopt(fd: fd_t, level: i32, optname: u32, optval: [*]const u8, optlen: socklen_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.setsockopt(fd, level, optname, optval, optlen));
}

pub fn getsockopt(fd: fd_t, level: i32, optname: u32, noalias optval: [*]u8, noalias optlen: *socklen_t) ErrnoError!usize {
    return errorFromSyscall(linux.getsockopt(fd, level, optname, optval, optlen));
}

pub fn sendmsg(fd: fd_t, msg: *const msghdr_const, flags: u32) ErrnoError!usize {
    return errorFromSyscall(linux.sendmsg(fd, msg, flags));
}

pub fn sendmmsg(fd: fd_t, msgvec: [*]mmsghdr, vlen: u32, flags: u32) ErrnoError!usize {
    return errorFromSyscall(linux.sendmmsg(fd, msgvec, vlen, flags));
}

pub fn connect(fd: fd_t, addr: *const anyopaque, len: socklen_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.connect(fd, addr, len));
}

pub fn recvmsg(fd: fd_t, msg: *msghdr, flags: u32) ErrnoError!usize {
    return errorFromSyscall(linux.recvmsg(fd, msg, flags));
}

pub fn recvmmsg(fd: fd_t, msgvec: ?[*]mmsghdr, vlen: u32, flags: u32, timeout: ?*timespec) ErrnoError!usize {
    return errorFromSyscall(linux.recvmmsg(fd, msgvec, vlen, flags, timeout));
}

pub fn recvfrom(
    fd: fd_t,
    noalias buffer: []u8,
    flags: u32,
    noalias addr: ?*sockaddr,
    noalias alen: ?*socklen_t,
) ErrnoError!usize {
    return errorFromSyscall(linux.recvfrom(fd, buffer.ptr, buffer.len, flags, addr, alen));
}

pub fn shutdown(fd: fd_t, how: i32) ErrnoError!void {
    _ = try errorFromSyscall(linux.shutdown(fd, how));
}

pub fn bind(fd: fd_t, addr: *const sockaddr, len: socklen_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.bind(fd, addr, len));
}

pub fn listen(fd: fd_t, backlog: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.listen(fd, backlog));
}

pub fn sendto(fd: fd_t, buffer: []const u8, flags: u32, addr: ?*const sockaddr, alen: socklen_t) ErrnoError!usize {
    return errorFromSyscall(linux.sendto(fd, buffer.ptr, buffer.len, flags, addr, alen));
}

pub fn sendfile(outfd: fd_t, infd: fd_t, offset: ?*i64, count: usize) ErrnoError!usize {
    return errorFromSyscall(linux.sendfile(outfd, infd, offset, count));
}

pub fn socketpair(domain: u32, socket_type: u32, protocol: u32) ErrnoError![2]fd_t {
    var fds: [2]fd_t = undefined;
    return errorFromSyscall(linux.socketpair(domain, socket_type, protocol, &fds));
}

pub fn accept(fd: fd_t, noalias addr: ?*sockaddr, noalias len: ?*socklen_t) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.accept(fd, addr, len)));
}

pub fn accept4(fd: fd_t, noalias addr: ?*sockaddr, noalias len: ?*socklen_t, flags: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.accept4(fd, addr, len, flags)));
}

pub fn statx(dirfd: fd_t, path: [*:0]const u8, flags: u32, mask: STATX, statx_buf: *Statx) ErrnoError!void {
    _ = try errorFromSyscall(linux.statx(dirfd, path, flags, mask, statx_buf));
}

pub fn listxattr(path: [*:0]const u8, list: [*]u8, size: usize) ErrnoError!usize {
    return errorFromSyscall(linux.listxattr(path, list, size));
}

pub fn llistxattr(path: [*:0]const u8, list: [*]u8, size: usize) ErrnoError!usize {
    return errorFromSyscall(linux.llistxattr(path, list, size));
}

pub fn flistxattr(fd: fd_t, list: [*]u8, size: usize) ErrnoError!usize {
    return errorFromSyscall(linux.flistxattr(fd, list, size));
}

pub fn getxattr(path: [*:0]const u8, name: [*:0]const u8, value: [*]u8, size: usize) ErrnoError!usize {
    return errorFromSyscall(linux.getxattr(path, name, value, size));
}

pub fn lgetxattr(path: [*:0]const u8, name: [*:0]const u8, value: [*]u8, size: usize) ErrnoError!usize {
    return errorFromSyscall(linux.lgetxattr(path, name, value, size));
}

pub fn fgetxattr(fd: fd_t, name: [*:0]const u8, value: [*]u8, size: usize) ErrnoError!usize {
    return errorFromSyscall(linux.fgetxattr(fd, name, value, size));
}

pub fn setxattr(path: [*:0]const u8, name: [*:0]const u8, value: [*]const u8, size: usize, flags: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.setxattr(path, name, value, size, flags));
}

pub fn lsetxattr(path: [*:0]const u8, name: [*:0]const u8, value: [*]const u8, size: usize, flags: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.lsetxattr(path, name, value, size, flags));
}

pub fn fsetxattr(fd: fd_t, name: [*:0]const u8, value: [*]const u8, size: usize, flags: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.fsetxattr(fd, name, value, size, flags));
}

pub fn removexattr(path: [*:0]const u8, name: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.removexattr(path, name));
}

pub fn lremovexattr(path: [*:0]const u8, name: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.lremovexattr(path, name));
}

pub fn fremovexattr(fd: usize, name: [*:0]const u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.fremovexattr(fd, name));
}

pub fn getcpu(cpu: ?*usize, node: ?*usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.getcpu(cpu, node));
}

pub fn sched_setparam(pid: pid_t, param: *const sched_param) ErrnoError!void {
    _ = try errorFromSyscall(linux.sched_setparam(pid, param));
}

pub fn sched_getparam(pid: pid_t, param: *sched_param) ErrnoError!void {
    _ = try errorFromSyscall(linux.sched_getparam(pid, param));
}

pub fn sched_setscheduler(pid: pid_t, policy: SCHED, param: *const sched_param) ErrnoError!void {
    _ = try errorFromSyscall(linux.sched_setscheduler(pid, policy, param));
}

pub fn sched_getscheduler(pid: pid_t) ErrnoError!SCHED {
    return @bitCast(@as(u32, @intCast(try errorFromSyscall(linux.sched_getscheduler(pid)))));
}

pub fn sched_get_priority_max(policy: SCHED) ErrnoError!u32 {
    return @intCast(try errorFromSyscall(linux.sched_get_priority_max(policy)));
}

pub fn sched_get_priority_min(policy: SCHED) ErrnoError!u32 {
    return @intCast(try errorFromSyscall(linux.sched_get_priority_min(policy)));
}

pub fn sched_setattr(pid: pid_t, attr: *const sched_attr, flags: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.sched_setattr(pid, attr, flags));
}

pub fn sched_getattr(pid: pid_t, attr: *sched_attr, size: usize, flags: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.sched_getattr(pid, attr, size, flags));
}

pub fn sched_rr_get_interval(pid: pid_t, tp: *timespec) ErrnoError!void {
    _ = try errorFromSyscall(linux.sched_rr_get_interval(pid, tp));
}

pub fn sched_yield() void {
    errorFromSyscall(linux.sched_yield()) catch unreachable;
}

pub fn sched_getaffinity(pid: pid_t, size: usize, set: *cpu_set_t) ErrnoError!usize {
    return errorFromSyscall(linux.sched_getaffinity(pid, size, set));
}

pub fn sched_setaffinity(pid: pid_t, set: *const cpu_set_t) !void {
    _ = try errorFromSyscall(linux.syscall3(.sched_setaffinity, @bitCast(@as(isize, pid))), @sizeOf(cpu_set_t), @intFromPtr(set));
}

pub fn epoll_create() ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.epoll_create()));
}

pub fn epoll_create1(flags: usize) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.epoll_create1(flags)));
}

pub fn epoll_ctl(epoll_fd: fd_t, op: u32, fd: fd_t, ev: ?*epoll_event) ErrnoError!void {
    _ = try errorFromSyscall(linux.epoll_ctl(epoll_fd, op, fd, ev));
}

pub fn epoll_wait(epoll_fd: fd_t, events: [*]epoll_event, maxevents: u32, timeout: i32) ErrnoError!usize {
    return errorFromSyscall(linux.epoll_wait(epoll_fd, events, maxevents, timeout));
}

pub fn epoll_pwait(epoll_fd: fd_t, events: [*]epoll_event, maxevents: u32, timeout: i32, sigmask: ?*const sigset_t) ErrnoError!usize {
    return errorFromSyscall(linux.epoll_pwait(epoll_fd, events, maxevents, timeout, sigmask));
}

pub fn eventfd(count: u32, flags: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.eventfd(count, flags)));
}

pub fn timerfd_create(clockid: timerfd_clockid_t, flags: TFD) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.timerfd_create(clockid, flags)));
}

pub fn timerfd_gettime(fd: fd_t, curr_value: *itimerspec) ErrnoError!void {
    _ = try errorFromSyscall(linux.timerfd_gettime(fd, curr_value));
}

pub fn timerfd_settime(fd: fd_t, flags: TFD.TIMER, new_value: *const itimerspec, old_value: ?*itimerspec) ErrnoError!void {
    _ = try errorFromSyscall(linux.timerfd_settime(fd, flags, new_value, old_value));
}

pub fn getitimer(which: ITIMER, curr_value: *itimerspec) ErrnoError!void {
    _ = try errorFromSyscall(linux.getitimer(which, curr_value));
}

pub fn setitimer(which: ITIMER, new_value: *const itimerspec, old_value: ?*itimerspec) ErrnoError!void {
    _ = try errorFromSyscall(linux.setitimer(which, new_value, old_value));
}

pub fn unshare(flags: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.unshare(flags));
}

pub fn setns(fd: fd_t, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.setns(fd, flags));
}

pub fn capget(hdrp: *cap_user_header_t, datap: *cap_user_data_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.capget(hdrp, datap));
}

pub fn capset(hdrp: *cap_user_header_t, datap: *const cap_user_data_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.capset(hdrp, datap));
}

pub fn sigaltstack(ss: ?*const stack_t, old_ss: ?*stack_t) ErrnoError!usize {
    return errorFromSyscall(linux.sigaltstack(ss, old_ss));
}

pub fn uname(uts: *utsname) ErrnoError!void {
    _ = try errorFromSyscall(linux.uname(uts));
}

pub fn io_uring_setup(entries: u32, p: *io_uring_params) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.io_uring_setup(entries, p)));
}

pub fn io_uring_enter(fd: fd_t, to_submit: u32, min_complete: u32, flags: u32, sig: ?*sigset_t) ErrnoError!usize {
    return errorFromSyscall(linux.io_uring_enter(fd, to_submit, min_complete, flags, sig));
}

pub fn io_uring_register(fd: fd_t, opcode: IORING_REGISTER, arg: ?*const anyopaque, nr_args: u32) ErrnoError!usize {
    return errorFromSyscall(linux.io_uring_register(fd, opcode, arg, nr_args));
}

pub fn memfd_create(name: [*:0]const u8, flags: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.memfd_create(name, flags)));
}

pub fn getrusage(who: i32, usage: *rusage) ErrnoError!void {
    _ = try errorFromSyscall(linux.getrusage(who, usage));
}

pub fn tcgetattr(fd: fd_t, termios_p: *termios) ErrnoError!usize {
    return errorFromSyscall(linux.tcgetattr(fd, termios_p));
}

pub fn tcsetattr(fd: fd_t, optional_action: TCSA, termios_p: *const termios) ErrnoError!usize {
    return errorFromSyscall(linux.tcsetattr(fd, optional_action, termios_p));
}

pub fn tcgetpgrp(fd: fd_t, pgrp: *pid_t) ErrnoError!usize {
    return errorFromSyscall(linux.tcgetpgrp(fd, pgrp));
}

pub fn tcsetpgrp(fd: fd_t, pgrp: *const pid_t) ErrnoError!usize {
    return errorFromSyscall(linux.tcsetpgrp(fd, pgrp));
}

pub fn tcdrain(fd: fd_t) ErrnoError!usize {
    return errorFromSyscall(linux.tcdrain(fd));
}

pub fn ioctl(fd: fd_t, request: u32, arg: usize) ErrnoError!usize {
    return errorFromSyscall(linux.ioctl(fd, request, arg));
}

pub fn signalfd(fd: fd_t, mask: *const sigset_t, flags: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.signalfd(fd, mask, flags)));
}

pub fn copy_file_range(fd_in: fd_t, off_in: ?*i64, fd_out: fd_t, off_out: ?*i64, len: usize, flags: u32) ErrnoError!usize {
    return errorFromSyscall(linux.copy_file_range(fd_in, off_in, fd_out, off_out, len, flags));
}

fn BpfResultType(comptime cmd: BPF.Cmd) type {
    return switch (cmd) {
        .map_create => fd_t,
        .prog_load => fd_t,
        else => void,
    };
}

pub fn bpf(comptime cmd: BPF.Cmd, attr: *BPF.Attr, size: u32) ErrnoError!BpfResultType(cmd) {
    const r = try errorFromSyscall(linux.bpf(cmd, attr, size));
    return switch (cmd) {
        .map_create => fdFromUsize(r),
        .prog_load => fdFromUsize(r),
        else => void,
    };
}

pub fn sync() void {
    linux.sync();
}

pub fn syncfs(fd: fd_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.syncfs(fd));
}

pub fn fsync(fd: fd_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.fsync(fd));
}

pub fn fdatasync(fd: fd_t) ErrnoError!void {
    _ = try errorFromSyscall(linux.fdatasync(fd));
}

pub fn prctl(op: i32, arg2: usize, arg3: usize, arg4: usize, arg5: usize) ErrnoError!usize {
    return errorFromSyscall(linux.prctl(op, arg2, arg3, arg4, arg5));
}

pub fn getrlimit(resource: rlimit_resource, rlim: *rlimit) ErrnoError!void {
    _ = try errorFromSyscall(linux.getrlimit(resource, rlim));
}

pub fn setrlimit(resource: rlimit_resource, rlim: *const rlimit) ErrnoError!void {
    _ = try errorFromSyscall(linux.setrlimit(resource, rlim));
}

pub fn prlimit(pid: pid_t, resource: rlimit_resource, new_limit: ?*const rlimit, old_limit: ?*rlimit) ErrnoError!void {
    _ = try errorFromSyscall(linux.prlimit(pid, resource, new_limit, old_limit));
}

pub fn mincore(address_range: []const u8, vec: [*]u8) ErrnoError!void {
    _ = try errorFromSyscall(linux.mincore(@constCast(address_range.ptr), address_range.len, vec));
}

pub fn pidfd_open(pid: pid_t, flags: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.pidfd_open(pid, flags)));
}

pub fn pidfd_getfd(pidfd: fd_t, targetfd: fd_t, flags: u32) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.pidfd_getfd(pidfd, targetfd, flags)));
}

pub fn pidfd_send_signal(pidfd: fd_t, sig: SIG, info: ?*siginfo_t, flags: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.pidfd_send_signal(pidfd, sig, info, flags));
}

pub fn process_vm_readv(pid: pid_t, local: []const iovec, remote: []const iovec_const, flags: usize) ErrnoError!usize {
    return errorFromSyscall(linux.process_vm_readv(pid, local, remote, flags));
}

pub fn process_vm_writev(pid: pid_t, local: []const iovec_const, remote: []const iovec_const, flags: usize) ErrnoError!usize {
    return errorFromSyscall(linux.process_vm_writev(pid, local, remote, flags));
}

pub fn madvise(address_range: []const u8, advice: u32) ErrnoError!void {
    _ = try errorFromSyscall(linux.madvise(@constCast(address_range.ptr), address_range.ptr, advice));
}

pub fn fadvise(fd: fd_t, offset: i64, len: i64, advice: usize) ErrnoError!void {
    _ = try errorFromSyscall(linux.fadvise(fd, offset, len, advice));
}

pub fn perf_event_open(
    attr: *perf_event_attr,
    pid: pid_t,
    cpu: i32,
    group_fd: fd_t,
    flags: usize,
) ErrnoError!fd_t {
    return fdFromUsize(try errorFromSyscall(linux.perf_event_open(attr, pid, cpu, group_fd, flags)));
}

pub fn seccomp(operation: u32, flags: u32, args: ?*const anyopaque) ErrnoError!usize {
    return errorFromSyscall(linux.seccomp(operation, flags, args));
}

pub fn ptrace(
    req: u32,
    pid: pid_t,
    addr: usize,
    data: usize,
    addr2: usize,
) ErrnoError!usize {
    return errorFromSyscall(linux.ptrace(req, pid, addr, data, addr2));
}

/// Query the page cache statistics of a file.
pub fn cachestat(
    /// The open file descriptor to retrieve statistics from.
    fd: fd_t,
    /// The byte range in `fd` to query.
    /// When `len > 0`, the range is `[off..off + len]`.
    /// When `len` == 0, the range is from `off` to the end of `fd`.
    cstat_range: *const cache_stat_range,
    /// The structure where page cache statistics are stored.
    cstat: *cache_stat,
    /// Currently unused, and must be set to `0`.
    flags: u32,
) ErrnoError!usize {
    return errorFromSyscall(linux.cachestat(fd, cstat_range, cstat, flags));
}

pub fn map_shadow_stack(addr: u64, size: u64, flags: u32) ErrnoError![*]u8 {
    return @ptrCast(try errorFromSyscall(linux.map_shadow_stack(addr, size, flags)));
}

pub fn sysinfo(info: *Sysinfo) ErrnoError!void {
    _ = try errorFromSyscall(linux.sysinfo(info));
}

inline fn wdFromUsize(value: usize) wd_t {
    return @as(wd_t, @intCast(value));
}

inline fn pidFromUsize(value: usize) pid_t {
    return @as(pid_t, @intCast(value));
}

inline fn fdFromUsize(value: usize) fd_t {
    return @as(fd_t, @intCast(value));
}
