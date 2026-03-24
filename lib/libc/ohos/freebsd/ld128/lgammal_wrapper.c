#include "libm.h"

long double __lgammal_r(long double, int *);

long double lgammal(long double x)
{
    return __lgammal_r(x, &__signgam);
}

long double lgammal_r(long double x, int *signgamp)
{
    return __lgammal_r(x, signgamp);
}
