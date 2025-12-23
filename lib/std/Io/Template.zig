//! Copy-pasteable template for creating custom Io implementations.

pub fn io(self: *@This()) std.Io {
    return .{
        .userdata = self,
        .vtable = &vtable,
    };
}

fn async(
    /// Corresponds to `Io.userdata`.
    userdata: ?*anyopaque,
    /// The pointer of this slice is an "eager" result value.
    /// The length is the size in bytes of the result type.
    /// This pointer's lifetime expires directly after the call to this function.
    result: []u8,
    result_alignment: std.mem.Alignment,
    /// Copied and then passed to `start`.
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ?*AnyFuture {
    _ = userdata; // autofix
    _ = result; // autofix
    _ = result_alignment; // autofix
    _ = context; // autofix
    _ = context_alignment; // autofix
    _ = start; // autofix
    @panic("Not implemented");
}

fn concurrent(
    /// Corresponds to `Io.userdata`.
    userdata: ?*anyopaque,
    result_len: usize,
    result_alignment: std.mem.Alignment,
    /// Copied and then passed to `start`.
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ConcurrentError!*AnyFuture {
    _ = userdata; // autofix
    _ = result_len; // autofix
    _ = result_alignment; // autofix
    _ = context; // autofix
    _ = context_alignment; // autofix
    _ = start; // autofix
    @panic("Not implemented");
}

fn await(
    /// Corresponds to `Io.userdata`.
    userdata: ?*anyopaque,
    /// The same value that was returned from `async`.
    any_future: *AnyFuture,
    /// Points to a buffer where the result is written.
    /// The length is equal to size in bytes of result type.
    result: []u8,
    result_alignment: std.mem.Alignment,
) void {
    _ = userdata; // autofix
    _ = any_future; // autofix
    _ = result; // autofix
    _ = result_alignment; // autofix
    @panic("Not implemented");
}

fn cancel(
    /// Corresponds to `Io.userdata`.
    userdata: ?*anyopaque,
    /// The same value that was returned from `async`.
    any_future: *AnyFuture,
    /// Points to a buffer where the result is written.
    /// The length is equal to size in bytes of result type.
    result: []u8,
    result_alignment: std.mem.Alignment,
) void {
    _ = userdata; // autofix
    _ = any_future; // autofix
    _ = result; // autofix
    _ = result_alignment; // autofix
    @panic("Not implemented");
}

fn groupAsync(
    /// Corresponds to `Io.userdata`.
    userdata: ?*anyopaque,
    /// Owner of the spawned async task.
    group: *Group,
    /// Copied and then passed to `start`.
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (*Group, context: *const anyopaque) void,
) void {
    _ = userdata; // autofix
    _ = group; // autofix
    _ = context; // autofix
    _ = context_alignment; // autofix
    _ = start; // autofix
    @panic("Not implemented");
}

fn groupConcurrent(
    /// Corresponds to `Io.userdata`.
    userdata: ?*anyopaque,
    /// Owner of the spawned async task.
    group: *Group,
    /// Copied and then passed to `start`.
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (*Group, context: *const anyopaque) void,
) ConcurrentError!void {
    _ = userdata; // autofix
    _ = group; // autofix
    _ = context; // autofix
    _ = context_alignment; // autofix
    _ = start; // autofix
    @panic("Not implemented");
}

fn groupWait(userdata: ?*anyopaque, group: *Group, token: *anyopaque) void {
    _ = userdata; // autofix
    _ = group; // autofix
    _ = token; // autofix
    @panic("Not implemented");
}

fn groupCancel(userdata: ?*anyopaque, group: *Group, token: *anyopaque) void {
    _ = userdata; // autofix
    _ = group; // autofix
    _ = token; // autofix
    @panic("Not implemented");
}

fn select(userdata: ?*anyopaque, futures: []const *AnyFuture) Cancelable!usize {
    _ = userdata; // autofix
    _ = futures; // autofix
    @panic("Not implemented");
}

fn mutexLock(userdata: ?*anyopaque, prev_state: Mutex.State, mutex: *Mutex) Cancelable!void {
    _ = userdata; // autofix
    _ = prev_state; // autofix
    _ = mutex; // autofix
    @panic("Not implemented");
}

fn mutexLockUncancelable(userdata: ?*anyopaque, prev_state: Mutex.State, mutex: *Mutex) void {
    _ = userdata; // autofix
    _ = prev_state; // autofix
    _ = mutex; // autofix
    @panic("Not implemented");
}

fn mutexUnlock(userdata: ?*anyopaque, prev_state: Mutex.State, mutex: *Mutex) void {
    _ = userdata; // autofix
    _ = prev_state; // autofix
    _ = mutex; // autofix
    @panic("Not implemented");
}

fn conditionWait(user: ?*anyopaque, cond: *Condition, mutex: *Mutex) Cancelable!void {
    _ = user; // autofix
    _ = cond; // autofix
    _ = mutex; // autofix
    @panic("Not implemented");
}

fn conditionWaitUncancelable(userdata: ?*anyopaque, cond: *Condition, mutex: *Mutex) void {
    _ = userdata; // autofix
    _ = cond; // autofix
    _ = mutex; // autofix
    @panic("Not implemented");
}

fn conditionWake(userdata: ?*anyopaque, cond: *Condition, wake: Condition.Wake) void {
    _ = userdata; // autofix
    _ = cond; // autofix
    _ = wake; // autofix
    @panic("Not implemented");
}

fn dirMake(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, dir_mode: Dir.Mode) Dir.MakeError!void {
    _ = userdata; // autofix
    _ = dir; // autofix
    _ = sub_path; // autofix
    _ = dir_mode; // autofix
    @panic("Not implemented");
}

fn dirMakePath(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, dir_mode: Dir.Mode) Dir.MakeError!void {
    _ = userdata; // autofix
    _ = dir; // autofix
    _ = sub_path; // autofix
    _ = dir_mode; // autofix
    @panic("Not implemented");
}

fn dirMakeOpenPath(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, open_options: Dir.OpenOptions) Dir.MakeOpenPathError!Dir {
    _ = userdata; // autofix
    _ = dir; // autofix
    _ = sub_path; // autofix
    _ = open_options; // autofix
    @panic("Not implemented");
}

fn dirStat(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    _ = userdata; // autofix
    _ = dir; // autofix
    @panic("Not implemented");
}

fn dirStatPath(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, stat_path_options: Dir.StatPathOptions) Dir.StatPathError!File.Stat {
    _ = userdata; // autofix
    _ = dir; // autofix
    _ = sub_path; // autofix
    _ = stat_path_options; // autofix
    @panic("Not implemented");
}

fn dirAccess(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, access_options: Dir.AccessOptions) Dir.AccessError!void {
    _ = userdata; // autofix
    _ = dir; // autofix
    _ = sub_path; // autofix
    _ = access_options; // autofix
    @panic("Not implemented");
}

fn dirCreateFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, create_flags: File.CreateFlags) File.OpenError!File {
    _ = userdata; // autofix
    _ = dir; // autofix
    _ = sub_path; // autofix
    _ = create_flags; // autofix
    @panic("Not implemented");
}

fn dirOpenFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, open_flags: File.OpenFlags) File.OpenError!File {
    _ = userdata; // autofix
    _ = dir; // autofix
    _ = sub_path; // autofix
    _ = open_flags; // autofix
    @panic("Not implemented");
}

fn dirOpenDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.OpenOptions) Dir.OpenError!Dir {
    _ = userdata; // autofix
    _ = dir; // autofix
    _ = sub_path; // autofix
    _ = options; // autofix
    @panic("Not implemented");
}

fn dirClose(userdata: ?*anyopaque, dir: Dir) void {
    _ = userdata; // autofix
    _ = dir; // autofix
    @panic("Not implemented");
}

fn fileStat(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    _ = userdata; // autofix
    _ = file; // autofix
    @panic("Not implemented");
}

fn fileClose(userdata: ?*anyopaque, file: File) void {
    _ = userdata; // autofix
    _ = file; // autofix
    @panic("Not implemented");
}

fn fileWriteStreaming(userdata: ?*anyopaque, file: File, buffer: [][]const u8) File.WriteStreamingError!usize {
    _ = userdata; // autofix
    _ = file; // autofix
    _ = buffer; // autofix
    @panic("Not implemented");
}

fn fileWritePositional(userdata: ?*anyopaque, file: File, buffer: [][]const u8, offset: u64) File.WritePositionalError!usize {
    _ = userdata; // autofix
    _ = file; // autofix
    _ = buffer; // autofix
    _ = offset; // autofix
    @panic("Not implemented");
}

fn fileReadStreaming(userdata: ?*anyopaque, file: File, data: [][]u8) File.Reader.Error!usize {
    _ = userdata; // autofix
    _ = file; // autofix
    _ = data; // autofix
    @panic("Not implemented");
}

fn fileReadPositional(userdata: ?*anyopaque, file: File, data: [][]u8, offset: u64) File.ReadPositionalError!usize {
    _ = userdata; // autofix
    _ = file; // autofix
    _ = data; // autofix
    _ = offset; // autofix
    @panic("Not implemented");
}

fn fileSeekBy(userdata: ?*anyopaque, file: File, relative_offset: i64) File.SeekError!void {
    _ = userdata; // autofix
    _ = file; // autofix
    _ = relative_offset; // autofix
    @panic("Not implemented");
}

fn fileSeekTo(userdata: ?*anyopaque, file: File, absolute_offset: u64) File.SeekError!void {
    _ = userdata; // autofix
    _ = file; // autofix
    _ = absolute_offset; // autofix
    @panic("Not implemented");
}

fn openSelfExe(userdata: ?*anyopaque, open_flags: File.OpenFlags) File.OpenSelfExeError!File {
    _ = userdata; // autofix
    _ = open_flags; // autofix
    @panic("Not implemented");
}

fn now(userdata: ?*anyopaque, clock: Clock) Clock.Error!Timestamp {
    _ = userdata; // autofix
    _ = clock; // autofix
    @panic("Not implemented");
}

fn sleep(userdata: ?*anyopaque, timeout: Timeout) SleepError!void {
    _ = userdata; // autofix
    _ = timeout; // autofix
    @panic("Not implemented");
}

fn netListenIp(userdata: ?*anyopaque, address: net.IpAddress, options: net.IpAddress.ListenOptions) net.IpAddress.ListenError!net.Server {
    _ = userdata; // autofix
    _ = address; // autofix
    _ = options; // autofix
    @panic("Not implemented");
}

fn netAccept(userdata: ?*anyopaque, server: net.Socket.Handle) net.Server.AcceptError!net.Stream {
    _ = userdata; // autofix
    _ = server; // autofix
    @panic("Not implemented");
}

fn netBindIp(userdata: ?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.BindOptions) net.IpAddress.BindError!net.Socket {
    _ = userdata; // autofix
    _ = address; // autofix
    _ = options; // autofix
    @panic("Not implemented");
}

fn netConnectIp(userdata: ?*anyopaque, address: *const net.IpAddress, options: net.IpAddress.ConnectOptions) net.IpAddress.ConnectError!net.Stream {
    _ = userdata; // autofix
    _ = address; // autofix
    _ = options; // autofix
    @panic("Not implemented");
}

fn netListenUnix(userdata: ?*anyopaque, address: *const net.UnixAddress, options: net.UnixAddress.ListenOptions) net.UnixAddress.ListenError!net.Socket.Handle {
    _ = userdata; // autofix
    _ = address; // autofix
    _ = options; // autofix
    @panic("Not implemented");
}

fn netConnectUnix(userdata: ?*anyopaque, address: *const net.UnixAddress) net.UnixAddress.ConnectError!net.Socket.Handle {
    _ = userdata; // autofix
    _ = address; // autofix
    @panic("Not implemented");
}

fn netSend(userdata: ?*anyopaque, socket_handle: net.Socket.Handle, outgoing_message: []net.OutgoingMessage, send_flags: net.SendFlags) struct { ?net.Socket.SendError, usize } {
    _ = userdata; // autofix
    _ = socket_handle; // autofix
    _ = outgoing_message; // autofix
    _ = send_flags; // autofix
    @panic("Not implemented");
}

fn netReceive(userdata: ?*anyopaque, socket_handle: net.Socket.Handle, message_buffer: []net.IncomingMessage, data_buffer: []u8, receive_flags: net.ReceiveFlags, timeout: Timeout) struct { ?net.Socket.ReceiveTimeoutError, usize } {
    _ = userdata; // autofix
    _ = socket_handle; // autofix
    _ = message_buffer; // autofix
    _ = data_buffer; // autofix
    _ = receive_flags; // autofix
    _ = timeout; // autofix
    @panic("Not implemented");
}

fn netRead(userdata: ?*anyopaque, src: net.Socket.Handle, data: [][]u8) net.Stream.Reader.Error!usize {
    _ = userdata; // autofix
    _ = src; // autofix
    _ = data; // autofix
    @panic("Not implemented");
}

fn netWrite(userdata: ?*anyopaque, dest: net.Socket.Handle, header: []const u8, data: []const []const u8, splat: usize) net.Stream.Writer.Error!usize {
    _ = userdata; // autofix
    _ = dest; // autofix
    _ = header; // autofix
    _ = data; // autofix
    _ = splat; // autofix
    @panic("Not implemented");
}

fn netClose(userdata: ?*anyopaque, handle: net.Socket.Handle) void {
    _ = userdata; // autofix
    _ = handle; // autofix
    @panic("Not implemented");
}

fn netInterfaceNameResolve(userdata: ?*anyopaque, interface_name: *const net.Interface.Name) net.Interface.Name.ResolveError!net.Interface {
    _ = userdata; // autofix
    _ = interface_name; // autofix
    @panic("Not implemented");
}

fn netInterfaceName(userdata: ?*anyopaque, net_interface: net.Interface) net.Interface.NameError!net.Interface.Name {
    _ = userdata; // autofix
    _ = net_interface; // autofix
    @panic("Not implemented");
}

fn netLookup(userdata: ?*anyopaque, host_name: net.HostName, queue: *Queue(net.HostName.LookupResult), options: net.HostName.LookupOptions) void {
    _ = userdata; // autofix
    _ = host_name; // autofix
    _ = queue; // autofix
    _ = options; // autofix
    @panic("Not implemented");
}

const vtable: std.Io.VTable = .{
    .async = async,
    .concurrent = concurrent,
    .await = await,
    .cancel = cancel,
    .select = select,

    .groupAsync = groupAsync,
    .groupConcurrent = groupConcurrent,
    .groupWait = groupWait,
    .groupCancel = groupCancel,

    .mutexLock = mutexLock,
    .mutexLockUncancelable = mutexLockUncancelable,
    .mutexUnlock = mutexUnlock,

    .conditionWait = conditionWait,
    .conditionWaitUncancelable = conditionWaitUncancelable,
    .conditionWake = conditionWake,

    .dirMake = dirMake,
    .dirMakePath = dirMakePath,
    .dirMakeOpenPath = dirMakeOpenPath,
    .dirStat = dirStat,
    .dirStatPath = dirStatPath,
    .fileStat = fileStat,
    .dirAccess = dirAccess,
    .dirCreateFile = dirCreateFile,
    .dirOpenFile = dirOpenFile,
    .dirOpenDir = dirOpenDir,
    .dirClose = dirClose,
    .fileClose = fileClose,
    .fileWriteStreaming = fileWriteStreaming,
    .fileWritePositional = fileWritePositional,
    .fileReadStreaming = fileReadStreaming,
    .fileReadPositional = fileReadPositional,
    .fileSeekBy = fileSeekBy,
    .fileSeekTo = fileSeekTo,
    .openSelfExe = openSelfExe,

    .now = now,
    .sleep = sleep,

    .netListenIp = netListenIp,
    .netListenUnix = netListenUnix,
    .netAccept = netAccept,
    .netBindIp = netBindIp,
    .netConnectIp = netConnectIp,
    .netConnectUnix = netConnectUnix,
    .netClose = netClose,
    .netRead = netRead,
    .netWrite = netWrite,

    .netSend = netSend,
    .netReceive = netReceive,
    .netInterfaceNameResolve = netInterfaceNameResolve,
    .netInterfaceName = netInterfaceName,
    .netLookup = netLookup,
};

const AnyFuture = std.Io.AnyFuture;
const Group = std.Io.Group;
const ConcurrentError = std.Io.ConcurrentError;
const Cancelable = std.Io.Cancelable;
const Mutex = std.Io.Mutex;
const Condition = std.Io.Condition;
const Dir = std.Io.Dir;
const File = std.Io.File;
const net = std.Io.net;
const Clock = std.Io.Clock;
const Timestamp = std.Io.Timestamp;
const Timeout = std.Io.Timeout;
const Queue = std.Io.Queue;
const SleepError = std.Io.SleepError;
const std = @import("std");
