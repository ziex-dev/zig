const std = @import("../../std.zig");
const ntdll = @import("ntdll.zig");
const ntstatus = @import("ntstatus.zig");

const windows = std.os.windows;

const ACCESS_MASK = windows.ACCESS_MASK;
const BOOL = windows.BOOL;
const CONDITION_VARIABLE = windows.CONDITION_VARIABLE;
const CONSOLE_SCREEN_BUFFER_INFO = windows.CONSOLE_SCREEN_BUFFER_INFO;
const CONTEXT = windows.CONTEXT;
const COORD = windows.COORD;
const DWORD = windows.DWORD;
const FARPROC = windows.FARPROC;
const FILETIME = windows.FILETIME;
const HANDLE = windows.HANDLE;
const HANDLER_ROUTINE = windows.HANDLER_ROUTINE;
const HMODULE = windows.HMODULE;
const INIT_ONCE = windows.INIT_ONCE;
const INIT_ONCE_FN = windows.INIT_ONCE_FN;
const LARGE_INTEGER = windows.LARGE_INTEGER;
const LPCSTR = windows.LPCSTR;
const LPCVOID = windows.LPCVOID;
const LPCWSTR = windows.LPCWSTR;
const LPTHREAD_START_ROUTINE = windows.LPTHREAD_START_ROUTINE;
const LPVOID = windows.LPVOID;
const LPWSTR = windows.LPWSTR;
const MODULEENTRY32 = windows.MODULEENTRY32;
const OVERLAPPED = windows.OVERLAPPED;
const OVERLAPPED_ENTRY = windows.OVERLAPPED_ENTRY;
const PMEMORY_BASIC_INFORMATION = windows.PMEMORY_BASIC_INFORMATION;
const PROCESS_INFORMATION = windows.PROCESS_INFORMATION;
const SECURITY_ATTRIBUTES = windows.SECURITY_ATTRIBUTES;
const SIZE_T = windows.SIZE_T;
const SRWLOCK = windows.SRWLOCK;
const STARTUPINFOW = windows.STARTUPINFOW;
const SYSTEM_INFO = windows.SYSTEM_INFO;
const UCHAR = windows.UCHAR;
const UINT = windows.UINT;
const ULONG = windows.ULONG;
const ULONG_PTR = windows.ULONG_PTR;
const va_list = windows.va_list;
const WCHAR = windows.WCHAR;
const WIN32_FIND_DATAW = windows.WIN32_FIND_DATAW;
const Win32Error = windows.Win32Error;
const WORD = windows.WORD;

// I/O - Filesystem

pub extern "kernel32" fn ReadDirectoryChangesW(
    hDirectory: HANDLE,
    lpBuffer: [*]align(@alignOf(windows.FILE_NOTIFY_INFORMATION)) u8,
    nBufferLength: DWORD,
    bWatchSubtree: BOOL,
    dwNotifyFilter: windows.FileNotifyChangeFilter,
    lpBytesReturned: ?*DWORD,
    lpOverlapped: ?*OVERLAPPED,
    lpCompletionRoutine: windows.LPOVERLAPPED_COMPLETION_ROUTINE,
) callconv(.winapi) BOOL;

// TODO: Wrapper around NtCancelIoFile.
pub extern "kernel32" fn CancelIo(
    hFile: HANDLE,
) callconv(.winapi) BOOL;

// TODO: Wrapper around NtCancelIoFileEx.
pub extern "kernel32" fn CancelIoEx(
    hFile: HANDLE,
    lpOverlapped: ?*OVERLAPPED,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn CreateFileW(
    lpFileName: LPCWSTR,
    dwDesiredAccess: ACCESS_MASK,
    dwShareMode: DWORD,
    lpSecurityAttributes: ?*SECURITY_ATTRIBUTES,
    dwCreationDisposition: DWORD,
    dwFlagsAndAttributes: DWORD,
    hTemplateFile: ?HANDLE,
) callconv(.winapi) HANDLE;

// TODO A bunch of logic around NtCreateNamedPipe
pub extern "kernel32" fn CreateNamedPipeW(
    lpName: LPCWSTR,
    dwOpenMode: DWORD,
    dwPipeMode: DWORD,
    nMaxInstances: DWORD,
    nOutBufferSize: DWORD,
    nInBufferSize: DWORD,
    nDefaultTimeOut: DWORD,
    lpSecurityAttributes: ?*const SECURITY_ATTRIBUTES,
) callconv(.winapi) HANDLE;

// TODO: Matches `STD_*_HANDLE` to peb().ProcessParameters.Standard*
pub extern "kernel32" fn GetStdHandle(
    nStdHandle: DWORD,
) callconv(.winapi) ?HANDLE;

// TODO: Wrapper around NtSetInformationFile + `FILE_POSITION_INFORMATION`.
//  `FILE_STANDARD_INFORMATION` is also used if dwMoveMethod is `FILE_END`
pub extern "kernel32" fn SetFilePointerEx(
    hFile: HANDLE,
    liDistanceToMove: LARGE_INTEGER,
    lpNewFilePointer: ?*LARGE_INTEGER,
    dwMoveMethod: DWORD,
) callconv(.winapi) BOOL;

// TODO: Wrapper around NtSetInformationFile + `FILE_BASIC_INFORMATION`
pub extern "kernel32" fn SetFileTime(
    hFile: HANDLE,
    lpCreationTime: ?*const FILETIME,
    lpLastAccessTime: ?*const FILETIME,
    lpLastWriteTime: ?*const FILETIME,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn WriteFile(
    in_hFile: HANDLE,
    in_lpBuffer: [*]const u8,
    in_nNumberOfBytesToWrite: DWORD,
    out_lpNumberOfBytesWritten: ?*DWORD,
    in_out_lpOverlapped: ?*OVERLAPPED,
) callconv(.winapi) BOOL;

// TODO: wrapper for NtQueryInformationFile + `FILE_STANDARD_INFORMATION`
pub extern "kernel32" fn GetFileSizeEx(
    hFile: HANDLE,
    lpFileSize: *LARGE_INTEGER,
) callconv(.winapi) BOOL;

// TODO: Wrapper around GetStdHandle + NtFlushBuffersFile.
pub extern "kernel32" fn FlushFileBuffers(
    hFile: HANDLE,
) callconv(.winapi) BOOL;

// TODO: Wrapper around NtSetInformationFile + `FILE_IO_COMPLETION_NOTIFICATION_INFORMATION`.
pub extern "kernel32" fn SetFileCompletionNotificationModes(
    FileHandle: HANDLE,
    Flags: UCHAR,
) callconv(.winapi) BOOL;

// TODO: `RtlGetCurrentDirectory_U(nBufferLength * 2, lpBuffer)`
pub extern "kernel32" fn GetCurrentDirectoryW(
    nBufferLength: DWORD,
    lpBuffer: ?[*]WCHAR,
) callconv(.winapi) DWORD;

pub extern "kernel32" fn ReadFile(
    hFile: HANDLE,
    lpBuffer: LPVOID,
    nNumberOfBytesToRead: DWORD,
    lpNumberOfBytesRead: ?*DWORD,
    lpOverlapped: ?*OVERLAPPED,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn GetSystemDirectoryW(
    lpBuffer: LPWSTR,
    uSize: UINT,
) callconv(.winapi) UINT;

// I/O - Kernel Objects

// TODO: Wrapper around GetStdHandle + NtDuplicateObject.
pub extern "kernel32" fn DuplicateHandle(
    hSourceProcessHandle: HANDLE,
    hSourceHandle: HANDLE,
    hTargetProcessHandle: HANDLE,
    lpTargetHandle: *HANDLE,
    dwDesiredAccess: ACCESS_MASK,
    bInheritHandle: BOOL,
    dwOptions: DWORD,
) callconv(.winapi) BOOL;

// TODO: Wrapper around GetStdHandle + NtQueryObject + NtSetInformationObject with .ObjectHandleFlagInformation.
pub extern "kernel32" fn SetHandleInformation(
    hObject: HANDLE,
    dwMask: DWORD,
    dwFlags: DWORD,
) callconv(.winapi) BOOL;

// TODO: Wrapper around NtRemoveIoCompletion.
pub extern "kernel32" fn GetQueuedCompletionStatus(
    CompletionPort: HANDLE,
    lpNumberOfBytesTransferred: *DWORD,
    lpCompletionKey: *ULONG_PTR,
    lpOverlapped: *?*OVERLAPPED,
    dwMilliseconds: DWORD,
) callconv(.winapi) BOOL;

// TODO: Wrapper around NtRemoveIoCompletionEx.
pub extern "kernel32" fn GetQueuedCompletionStatusEx(
    CompletionPort: HANDLE,
    lpCompletionPortEntries: [*]OVERLAPPED_ENTRY,
    ulCount: ULONG,
    ulNumEntriesRemoved: *ULONG,
    dwMilliseconds: DWORD,
    fAlertable: BOOL,
) callconv(.winapi) BOOL;

// TODO: Wrapper around NtSetIoCompletion with `IoStatus = .SUCCESS`.
pub extern "kernel32" fn PostQueuedCompletionStatus(
    CompletionPort: HANDLE,
    dwNumberOfBytesTransferred: DWORD,
    dwCompletionKey: ULONG_PTR,
    lpOverlapped: ?*OVERLAPPED,
) callconv(.winapi) BOOL;

// TODO:
// GetOverlappedResultEx with bAlertable=false, which calls: GetStdHandle + WaitForSingleObjectEx.
// Uses the SwitchBack system to run implementations for older programs; Do we care about this?
pub extern "kernel32" fn GetOverlappedResult(
    hFile: HANDLE,
    lpOverlapped: *OVERLAPPED,
    lpNumberOfBytesTransferred: *DWORD,
    bWait: BOOL,
) callconv(.winapi) BOOL;

// TODO: Wrapper around NtCreateIoCompletion + NtSetInformationFile with FILE_COMPLETION_INFORMATION.
// This would be better splitting into two functions.
pub extern "kernel32" fn CreateIoCompletionPort(
    FileHandle: HANDLE,
    ExistingCompletionPort: ?HANDLE,
    CompletionKey: ULONG_PTR,
    NumberOfConcurrentThreads: DWORD,
) callconv(.winapi) ?HANDLE;

// TODO: Wrapper around RtlReportSilentProcessExit + NtTerminateProcess.
pub extern "kernel32" fn TerminateProcess(
    hProcess: HANDLE,
    uExitCode: UINT,
) callconv(.winapi) BOOL;

// TODO: WaitForSingleObjectEx with bAlertable=false.
pub extern "kernel32" fn WaitForSingleObject(
    hHandle: HANDLE,
    dwMilliseconds: DWORD,
) callconv(.winapi) DWORD;

// TODO: Wrapper for GetStdHandle + NtWaitForSingleObject.
// Sets up an activation context before calling NtWaitForSingleObject.
pub extern "kernel32" fn WaitForSingleObjectEx(
    hHandle: HANDLE,
    dwMilliseconds: DWORD,
    bAlertable: BOOL,
) callconv(.winapi) DWORD;

// TODO: WaitForMultipleObjectsEx with alertable=false
pub extern "kernel32" fn WaitForMultipleObjects(
    nCount: DWORD,
    lpHandle: [*]const HANDLE,
    bWaitAll: BOOL,
    dwMilliseconds: DWORD,
) callconv(.winapi) DWORD;

// TODO: Wrapper around NtWaitForMultipleObjects.
pub extern "kernel32" fn WaitForMultipleObjectsEx(
    nCount: DWORD,
    lpHandle: [*]const HANDLE,
    bWaitAll: BOOL,
    dwMilliseconds: DWORD,
    bAlertable: BOOL,
) callconv(.winapi) DWORD;

// Process Management

pub extern "kernel32" fn CreateProcessW(
    lpApplicationName: ?LPCWSTR,
    lpCommandLine: ?LPWSTR,
    lpProcessAttributes: ?*SECURITY_ATTRIBUTES,
    lpThreadAttributes: ?*SECURITY_ATTRIBUTES,
    bInheritHandles: BOOL,
    dwCreationFlags: windows.CreateProcessFlags,
    lpEnvironment: ?[*:0]const u16,
    lpCurrentDirectory: ?LPCWSTR,
    lpStartupInfo: *STARTUPINFOW,
    lpProcessInformation: *PROCESS_INFORMATION,
) callconv(.winapi) BOOL;

// TODO: implement via ntdll instead
pub extern "kernel32" fn SleepEx(
    dwMilliseconds: DWORD,
    bAlertable: BOOL,
) callconv(.winapi) DWORD;

// TODO: Wrapper around NtQueryInformationProcess with `PROCESS_BASIC_INFORMATION`.
pub extern "kernel32" fn GetExitCodeProcess(
    hProcess: HANDLE,
    lpExitCode: *DWORD,
) callconv(.winapi) BOOL;

// TODO: Wrapper around RtlSetEnvironmentVar.
pub extern "kernel32" fn SetEnvironmentVariableW(
    lpName: LPCWSTR,
    lpValue: ?LPCWSTR,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn CreateToolhelp32Snapshot(
    dwFlags: DWORD,
    th32ProcessID: DWORD,
) callconv(.winapi) HANDLE;

// Threading

// TODO: Already a wrapper for this, see `windows.GetCurrentThreadId`.
pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) DWORD;

// TODO: CreateRemoteThread with hProcess=NtCurrentProcess().
pub extern "kernel32" fn CreateThread(
    lpThreadAttributes: ?*SECURITY_ATTRIBUTES,
    dwStackSize: SIZE_T,
    lpStartAddress: LPTHREAD_START_ROUTINE,
    lpParameter: ?LPVOID,
    dwCreationFlags: DWORD,
    lpThreadId: ?*DWORD,
) callconv(.winapi) ?HANDLE;

// Locks, critical sections, initializers

pub extern "kernel32" fn InitOnceExecuteOnce(
    InitOnce: *INIT_ONCE,
    InitFn: INIT_ONCE_FN,
    Parameter: ?*anyopaque,
    Context: ?*anyopaque,
) callconv(.winapi) BOOL;

// TODO:
//  - dwMilliseconds -> LARGE_INTEGER.
//  - RtlSleepConditionVariableSRW
//  - return rc != .TIMEOUT
pub extern "kernel32" fn SleepConditionVariableSRW(
    ConditionVariable: *CONDITION_VARIABLE,
    SRWLock: *SRWLOCK,
    dwMilliseconds: DWORD,
    Flags: ULONG,
) callconv(.winapi) BOOL;

// Console management

pub extern "kernel32" fn GetConsoleMode(
    hConsoleHandle: HANDLE,
    lpMode: *DWORD,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn SetConsoleMode(
    hConsoleHandle: HANDLE,
    dwMode: DWORD,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn GetConsoleScreenBufferInfo(
    hConsoleOutput: HANDLE,
    lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn SetConsoleTextAttribute(
    hConsoleOutput: HANDLE,
    wAttributes: WORD,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn SetConsoleCtrlHandler(
    HandlerRoutine: ?HANDLER_ROUTINE,
    Add: BOOL,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn SetConsoleOutputCP(
    wCodePageID: UINT,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) UINT;

pub extern "kernel32" fn FillConsoleOutputAttribute(
    hConsoleOutput: HANDLE,
    wAttribute: WORD,
    nLength: DWORD,
    dwWriteCoord: COORD,
    lpNumberOfAttrsWritten: *DWORD,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn FillConsoleOutputCharacterW(
    hConsoleOutput: HANDLE,
    cCharacter: WCHAR,
    nLength: DWORD,
    dwWriteCoord: COORD,
    lpNumberOfCharsWritten: *DWORD,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn SetConsoleCursorPosition(
    hConsoleOutput: HANDLE,
    dwCursorPosition: COORD,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn WriteConsoleW(
    hConsoleOutput: HANDLE,
    lpBuffer: [*]const u16,
    nNumberOfCharsToWrite: DWORD,
    lpNumberOfCharsWritten: ?*DWORD,
    lpReserved: ?LPVOID,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn ReadConsoleOutputCharacterW(
    hConsoleOutput: HANDLE,
    lpCharacter: [*]u16,
    nLength: DWORD,
    dwReadCoord: COORD,
    lpNumberOfCharsRead: *DWORD,
) callconv(.winapi) BOOL;

// Code Libraries/Modules

// TODO: Wrapper around LdrGetDllFullName.
pub extern "kernel32" fn GetModuleFileNameW(
    hModule: ?HMODULE,
    lpFilename: [*]WCHAR,
    nSize: DWORD,
) callconv(.winapi) DWORD;

extern "kernel32" fn K32GetModuleFileNameExW(
    hProcess: HANDLE,
    hModule: ?HMODULE,
    lpFilename: LPWSTR,
    nSize: DWORD,
) callconv(.winapi) DWORD;
pub const GetModuleFileNameExW = K32GetModuleFileNameExW;

// TODO: Wrapper around ntdll.LdrGetDllHandle, which is a wrapper around LdrGetDllHandleEx
pub extern "kernel32" fn GetModuleHandleW(
    lpModuleName: ?LPCWSTR,
) callconv(.winapi) ?HMODULE;

pub extern "kernel32" fn Module32First(
    hSnapshot: HANDLE,
    lpme: *MODULEENTRY32,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn Module32Next(
    hSnapshot: HANDLE,
    lpme: *MODULEENTRY32,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn LoadLibraryW(
    lpLibFileName: LPCWSTR,
) callconv(.winapi) ?HMODULE;

pub extern "kernel32" fn LoadLibraryExW(
    lpLibFileName: LPCWSTR,
    hFile: ?HANDLE,
    dwFlags: DWORD,
) callconv(.winapi) ?HMODULE;

pub extern "kernel32" fn GetProcAddress(
    hModule: HMODULE,
    lpProcName: LPCSTR,
) callconv(.winapi) ?FARPROC;

pub extern "kernel32" fn FreeLibrary(
    hModule: HMODULE,
) callconv(.winapi) BOOL;

// Error Management

pub extern "kernel32" fn FormatMessageW(
    dwFlags: DWORD,
    lpSource: ?LPCVOID,
    dwMessageId: Win32Error,
    dwLanguageId: DWORD,
    lpBuffer: LPWSTR,
    nSize: DWORD,
    Arguments: ?*va_list,
) callconv(.winapi) DWORD;

// TODO: Getter for teb().LastErrorValue.
pub extern "kernel32" fn GetLastError() callconv(.winapi) Win32Error;

// TODO: Wrapper around RtlSetLastWin32Error.
pub extern "kernel32" fn SetLastError(
    dwErrCode: Win32Error,
) callconv(.winapi) void;

// Everything Else

pub extern "kernel32" fn GetSystemInfo(
    lpSystemInfo: *SYSTEM_INFO,
) callconv(.winapi) void;

pub extern "kernel32" fn VirtualFreeEx(hProcess: HANDLE, lpAddress: LPVOID, dwSize: SIZE_T, dwFreeType: DWORD) callconv(.winapi) BOOL;

pub extern "kernel32" fn VirtualQueryEx(hProcess: HANDLE, lpAddress: ?LPCVOID, lpBuffer: PMEMORY_BASIC_INFORMATION, dwLength: SIZE_T) callconv(.winapi) SIZE_T;

pub extern "kernel32" fn VirtualProtectEx(
    hProcess: HANDLE,
    lpAddress: LPVOID,
    dwSize: SIZE_T,
    flNewProtect: DWORD,
    lpflOldProtect: *DWORD,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn OpenProcess(
    dwDesiredAccess: DWORD,
    bInheritHandle: BOOL,
    dwProcessId: DWORD,
) callconv(.winapi) ?HANDLE;

pub extern "kernel32" fn CreateRemoteThread(
    hProcess: HANDLE,
    lpThreadAttributes: ?*SECURITY_ATTRIBUTES,
    dwStackSize: SIZE_T,
    lpStartAddress: LPTHREAD_START_ROUTINE,
    lpParameter: LPVOID,
    dwCreationFlags: DWORD,
    lpThreadId: ?*DWORD,
) callconv(.winapi) ?HANDLE;

pub extern "kernel32" fn GetThreadContext(
    hThread: HANDLE,
    lpContext: *CONTEXT,
) callconv(.winapi) BOOL;

pub extern "kernel32" fn SetThreadContext(hThread: HANDLE, lpContext: *const CONTEXT) callconv(.winapi) BOOL;

pub extern "kernel32" fn ResumeThread(hThread: HANDLE) callconv(.winapi) DWORD;

pub extern "kernel32" fn SuspendThread(hThread: HANDLE) callconv(.winapi) DWORD;

pub extern "kernel32" fn GetExitCodeThread(hThread: HANDLE, lpExitCode: *DWORD) callconv(.winapi) BOOL;

pub fn GetCurrentProcess() HANDLE {
    return @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));
}

const MEM = windows.MEM;
const PAGE = windows.PAGE;

pub fn VirtualAllocEx(
    ProcessHandle: HANDLE,
    BaseAddress: ?LPVOID,
    RegionSize: SIZE_T,
    AllocationType: MEM.ALLOCATE,
    Protect: PAGE,
) !LPVOID {
    var base_addr: ?LPVOID = BaseAddress;
    var region_size: SIZE_T = RegionSize;

    const status = ntdll.NtAllocateVirtualMemory(
        ProcessHandle,
        @ptrCast(&base_addr),
        0,
        &region_size,
        AllocationType,
        Protect,
    );

    if (status == .SUCCESS) {
        return base_addr orelse error.Unexpected;
    }

    const code: Win32Error = @enumFromInt(@as(u16, @truncate(ntdll.RtlNtStatusToDosError(status))));
    return switch (code) {
        .ACCESS_DENIED => error.AccessDenied,
        .NOT_ENOUGH_MEMORY, .OUTOFMEMORY => error.OutOfMemory,
        .INVALID_PARAMETER => error.InvalidParameter,
        .INVALID_HANDLE => error.InvalidHandle,
        .SUCCESS => error.Unexpected,
        else => error.UnexpectedError,
    };
}

pub fn VirtualAlloc(
    BaseAddress: ?LPVOID,
    RegionSize: SIZE_T,
    AllocationType: MEM.ALLOCATE,
    Protect: PAGE,
) !LPVOID {
    return try VirtualAllocEx(
        GetCurrentProcess(),
        BaseAddress,
        RegionSize,
        AllocationType,
        Protect,
    );
}

// --- 单元测试用例 ---

const MEM_COMMIT = 0x1000;
const MEM_RESERVE = 0x2000;
const PAGE_READWRITE = 0x04;

test "VirtualAlloc - 成功分配并写入内存" {
    const size = 4096;

    const ptr = try VirtualAlloc(null, size, windows.MEM.ALLOCATE{ .RESERVE = true, .COMMIT = true }, PAGE{ .READWRITE = true });

    // 确保分配到了地址
    try std.testing.expect(@intFromPtr(ptr) != 0);

    // 测试内存可读写性
    const slice: [*]u8 = @ptrCast(ptr);
    slice[0] = 0xDE;
    slice[size - 1] = 0xAD;

    try std.testing.expectEqual(slice[0], 0xDE);
    try std.testing.expectEqual(slice[size - 1], 0xAD);
}

test "VirtualAllocEx - 错误处理测试 (非法参数)" {
    const result = VirtualAllocEx(
        GetCurrentProcess(),
        null,
        4096,
        windows.MEM.ALLOCATE{ .RESERVE = false, .COMMIT = false }, // 非法参数
        PAGE{ .READWRITE = true },
    );

    try std.testing.expectError(error.InvalidParameter, result);
}
