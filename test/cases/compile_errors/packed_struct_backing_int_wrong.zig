export fn entry1() void {
    _ = @sizeOf(bitpack struct(u32) {
        x: u1,
        y: u24,
        z: u4,
    });
}
export fn entry2() void {
    _ = @sizeOf(bitpack struct(i31) {
        x: u4,
        y: u24,
        z: u4,
    });
}

export fn entry3() void {
    _ = @sizeOf(bitpack struct(void) {
        x: void,
    });
}

export fn entry4() void {
    _ = @sizeOf(bitpack struct(void) {});
}

export fn entry5() void {
    _ = @sizeOf(bitpack struct(noreturn) {});
}

export fn entry6() void {
    _ = @sizeOf(bitpack struct(f64) {
        x: u32,
        y: f32,
    });
}

export fn entry7() void {
    _ = @sizeOf(bitpack struct(*u32) {
        x: u4,
        y: u24,
        z: u4,
    });
}

// error
//
// :2:25: error: backing integer bit width does not match total bit width of fields
// :2:32: note: backing integer 'u32' has bit width '32'
// :2:25: note: struct fields have total bit width '29'
// :9:25: error: backing integer bit width does not match total bit width of fields
// :9:32: note: backing integer 'i31' has bit width '31'
// :9:25: note: struct fields have total bit width '32'
// :17:32: error: expected backing integer type, found 'void'
// :23:32: error: expected backing integer type, found 'void'
// :27:32: error: expected backing integer type, found 'noreturn'
// :31:32: error: expected backing integer type, found 'f64'
// :38:32: error: expected backing integer type, found '*u32'
