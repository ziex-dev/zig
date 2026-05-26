export fn foo() void {
    asm volatile ("" ::: undefined);
}

// error
//
// :2:26: error: use of undefined value here causes illegal behavior
