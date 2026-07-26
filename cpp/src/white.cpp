#include "vnoise/internal.h"

namespace vnoise {

static inline unsigned int hash3(unsigned int x, unsigned int y, unsigned int z) {
    unsigned int h = x * 374761393u + y * 668265263u + z * 2147483647u;
    h = (h ^ (h >> 13)) * 1274126177u;
    return h ^ (h >> 16);
}

static inline float to_range(unsigned int h) {
    return ((float)(h >> 8) / (float)0x00FFFFFF) * 2.0f - 1.0f;
}

} // namespace vnoise

extern "C" {

VNOISE_API float white2_eval(const noise_state_t* s, int ix, int iy) {
    if (!s) return 0;
    (void)s;
    return vnoise::to_range(vnoise::hash3((unsigned int)ix, (unsigned int)iy, 0u));
}

VNOISE_API float white3_eval(const noise_state_t* s, int ix, int iy, int iz) {
    if (!s) return 0;
    (void)s;
    return vnoise::to_range(vnoise::hash3((unsigned int)ix, (unsigned int)iy, (unsigned int)iz));
}

}