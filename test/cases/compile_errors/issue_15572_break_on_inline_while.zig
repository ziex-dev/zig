const std = @import("std");

pub const DwarfSection = enum {
    eh_frame,
    eh_frame_hdr,
};

pub fn main() void {
    const section = inline for (@typeInfo(DwarfSection).@"enum".fields, 0..) |section, i| {
        if (std.mem.eql(u8, section.name, "eh_frame")) break i;
    };

    _ = section;
}

// error
//
// :9:28: error: incompatible types: 'usize' and 'void'
