export fn foo() void {
    var a: u8 = 0;
    var b: u8 = 0;
    asm (""
        : [a] "" (a),
          [a] "" (b),
    );
}

export fn bar() void {
    const a: u8 = 0;
    const b: u8 = 0;
    asm volatile (""
        :
        : [a] "" (a),
          [a] "" (b),
    );
}

export fn baz() void {
    var a: u8 = 0;
    const b: u8 = 0;
    asm (""
        : [a] "" (a),
        : [a] "" (b),
    );
}

// error
//
// :6:12: error: duplicate assembly output name
// :5:12: note: previously declared here
// :16:12: error: duplicate assembly input name
// :15:12: note: previously declared here
// :25:12: error: duplicate assembly input name
// :24:12: note: previously declared here
