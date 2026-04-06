const std = @import("../../std.zig");
const assert = std.debug.assert;
const windows = std.os.windows;

const USHORT = windows.USHORT;
const LONG = windows.LONG;

pub const GROUP = u32;
pub const ADDRESS_FAMILY = AF;

// Microsoft use the signed c_int for this, but it should never be negative
pub const socklen_t = u32;

pub const TCP = struct {
    pub const NODELAY = 1;
    pub const EXPEDITED_1122 = 2;
    pub const OFFLOAD_NO_PREFERENCE = 0;
    pub const OFFLOAD_NOT_PREFERRED = 1;
    pub const OFFLOAD_PREFERRED = 2;
    pub const KEEPALIVE = 3;
    pub const MAXSEG = 4;
    pub const MAXRT = 5;
    pub const STDURG = 6;
    pub const NOURG = 7;
    pub const ATMARK = 8;
    pub const NOSYNRETRIES = 9;
    pub const TIMESTAMPS = 10;
    pub const OFFLOAD_PREFERENCE = 11;
    pub const CONGESTION_ALGORITHM = 12;
    pub const DELAY_FIN_ACK = 13;
    pub const MAXRTMS = 14;
    pub const FASTOPEN = 15;
    pub const KEEPCNT = 16;
    pub const KEEPINTVL = 17;
    pub const FAIL_CONNECT_ON_ICMP_ERROR = 18;
    pub const ICMP_ERROR_INFO = 19;
    pub const BSDURGENT = 28672;
};

pub const AF = enum(u16) {
    UNSPEC = 0,
    UNIX = 1,
    INET = 2,
    IMPLINK = 3,
    PUP = 4,
    CHAOS = 5,
    IPX = 6,
    ISO = 7,
    ECMA = 8,
    DATAKIT = 9,
    CCITT = 10,
    SNA = 11,
    DECnet = 12,
    DLI = 13,
    LAT = 14,
    HYLINK = 15,
    APPLETALK = 16,
    NETBIOS = 17,
    VOICEVIEW = 18,
    FIREFOX = 19,
    UNKNOWN1 = 20,
    BAN = 21,
    ATM = 22,
    INET6 = 23,
    CLUSTER = 24,
    @"12844" = 25,
    IRDA = 26,
    NETDES = 28,
    MAX = 29,
    TCNMESSAGE = 30,
    ICLFXBM = 31,
    BTH = 32,
    LINK = 33,
    HYPERV = 34,
    _,

    pub const NS: AF = .IPS;
    pub const TCNPROCESS: AF = .MAX;
};

pub const SOCK = packed struct(u32) {
    type: TYPE = .DEFAULT,
    flags: Flags = .{},

    pub const TYPE = enum(u7) {
        DEFAULT = 0,
        STREAM = 1,
        DGRAM = 2,
        RAW = 3,
        RDM = 4,
        SEQPACKET = 5,
        _,
    };

    const Flags = packed struct(u25) {
        _: u25 = 0,
    };
};

pub const SOL = enum(u16) {
    IRLMP = 255,
    SOCKET = 65535,
    _,
};

pub const SO = enum(u16) {
    DEBUG = 1,
    ACCEPTCONN = 2,
    REUSEADDR = 4,
    KEEPALIVE = 8,
    DONTROUTE = 16,
    BROADCAST = 32,
    USELOOPBACK = 64,
    LINGER = 128,
    OOBINLINE = 256,
    SNDBUF = 4097,
    RCVBUF = 4098,
    SNDLOWAT = 4099,
    RCVLOWAT = 4100,
    SNDTIMEO = 4101,
    RCVTIMEO = 4102,
    ERROR = 4103,
    TYPE = 4104,
    BSP_STATE = 4105,
    GROUP_ID = 8193,
    GROUP_PRIORITY = 8194,
    MAX_MSG_SIZE = 8195,
    CONDITIONAL_ACCEPT = 12290,
    PAUSE_ACCEPT = 12291,
    COMPARTMENT_ID = 12292,
    RANDOMIZE_PORT = 12293,
    PORT_SCALABILITY = 12294,
    REUSE_UNICASTPORT = 12295,
    REUSE_MULTICASTPORT = 12296,
    ORIGINAL_DST = 12303,
    PROTOCOL_INFOA = 8196,
    PROTOCOL_INFOW = 8197,
    CONNDATA = 28672,
    CONNOPT = 28673,
    DISCDATA = 28674,
    DISCOPT = 28675,
    CONNDATALEN = 28676,
    CONNOPTLEN = 28677,
    DISCDATALEN = 28678,
    DISCOPTLEN = 28679,
    OPENTYPE = 28680,
    MAXDG = 28681,
    MAXPATHDG = 28682,
    UPDATE_ACCEPT_CONTEXT = 28683,
    CONNECT_TIME = 28684,
    UPDATE_CONNECT_CONTEXT = 28688,
    _,

    pub const SYNCHRONOUS_ALERT: AF = .DONTROUTE;
    pub const SYNCHRONOUS_NONALERT: AF = .BROADCAST;

    pub const UNIX_PATH = 0x98000000;
};

pub const MSG = packed struct(u32) {
    OOB: bool = false,
    PEEK: bool = false,
    DONTROUTE: bool = false,
    WAITALL: bool = false,
    INTERRUPT: bool = false,
    PUSH_IMMEDIATE: bool = false,
    _7: u2 = 0,
    TRUNC: bool = false,
    CTRUNC: bool = false,
    BCAST: bool = false,
    MCAST: bool = false,
    _13: u3 = 0,
    PARTIAL: bool = false,
    _17: u16 = 0,

    pub const MAXIOVLEN = 16;
};

pub const IPPROTO = enum(u16) {
    IP = 0,
    ICMP = 1,
    IGMP = 2,
    GGP = 3,
    TCP = 6,
    PUP = 12,
    UDP = 17,
    IDP = 22,
    ND = 77,
    RM = 113,
    RAW = 255,
    MAX = 256,
    _,
};

pub const FLOWSPEC = extern struct {
    TokenRate: u32,
    TokenBucketSize: u32,
    PeakBandwidth: u32,
    Latency: u32,
    DelayVariation: u32,
    ServiceType: u32,
    MaxSduSize: u32,
    MinimumPolicedSize: u32,
};

pub const sockproto = extern struct {
    sp_family: u16,
    sp_protocol: u16,
};

pub const linger = extern struct {
    onoff: u16,
    linger: u16,
};

pub const sockaddr = extern struct {
    family: ADDRESS_FAMILY,
    data: [14]u8,

    pub const SS_MAXSIZE = 128;
    pub const storage = extern struct {
        family: ADDRESS_FAMILY align(8),
        padding: [SS_MAXSIZE - @sizeOf(ADDRESS_FAMILY)]u8 = undefined,

        comptime {
            assert(@sizeOf(storage) == SS_MAXSIZE);
            assert(@alignOf(storage) == 8);
        }
    };

    /// IPv4 socket address
    pub const in = extern struct {
        family: ADDRESS_FAMILY = .INET,
        port: USHORT,
        addr: u32,
        zero: [8]u8 = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };

    /// IPv6 socket address
    pub const in6 = extern struct {
        family: ADDRESS_FAMILY = .INET6,
        port: USHORT,
        flowinfo: u32,
        addr: [16]u8,
        scope_id: u32,
    };

    /// UNIX domain socket address
    pub const un = extern struct {
        family: ADDRESS_FAMILY = .UNIX,
        path: [108]u8,
    };
};

pub const hostent = extern struct {
    h_name: [*]u8,
    h_aliases: **i8,
    h_addrtype: i16,
    h_length: i16,
    h_addr_list: **i8,
};

pub const timeval = extern struct {
    sec: LONG,
    usec: LONG,
};
