// Shared library with a constructor that calls malloc().
// When the TSan runtime is not initialized before shared library
// constructors, this malloc() call crashes in TSan's uninitialized
// interceptor (SIGSEGV). See https://codeberg.org/ziglang/zig/issues/32106

#include <stdlib.h>

__attribute__((constructor))
static void my_ctor(void) {
    void *p = malloc(64);
    free(p);
}

int lib_function(void) { return 42; }
