pub export fn entry() void {
    const T = bitpack struct {
        a: u65535,
        b: u65535,
    };
    @compileLog(@sizeOf(T));
}

// error
//
// :2:23: error: packed struct bit width '131070' exceeds maximum bit width of 65535
