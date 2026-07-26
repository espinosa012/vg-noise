#include "vnoise/internal.h"

namespace vnoise {

void seed_rng(unsigned long long seed, unsigned long long* sm,
              unsigned int* xs) {
    sm[0] = seed;
    unsigned int s32 = (unsigned int)(splitmix64(sm) >> 32);
    if (s32 == 0) s32 = 0x12345678u;
    xs[0] = s32;
}

} // namespace vnoise