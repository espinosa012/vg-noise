#include "vnoise/internal.h"

extern "C" {

VNOISE_API void noise_init(noise_state_t* s, unsigned long long seed) {
    if (!s) return;
    s->seed = seed;
    for (int i = 0; i < 256; ++i) s->perm[i] = (unsigned int)i;

    unsigned long long sm;
    unsigned int xs;
    vnoise::seed_rng(seed, &sm, &xs);

    for (int i = 255; i > 0; --i) {
        unsigned int r = vnoise::xorshift32(&xs);
        int j = (int)(r % (unsigned int)(i + 1));
        unsigned int tmp = s->perm[i];
        s->perm[i] = s->perm[j];
        s->perm[j] = tmp;
    }
    for (int i = 0; i < 256; ++i) s->perm[i + 256] = s->perm[i];
}

}