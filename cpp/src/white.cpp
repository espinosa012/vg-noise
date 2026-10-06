#include "vnoise/internal.h"

namespace vnoise {

// Integer hash of the cell coordinates mixed with a per-seed key, so each
// seed yields an independent white-noise field.
static inline unsigned int hash4(unsigned int x, unsigned int y, unsigned int z, unsigned int k) {
    unsigned int h = x * 374761393u + y * 668265263u + z * 2147483647u + k * 3266489917u;
    h = (h ^ (h >> 13)) * 1274126177u;
    return h ^ (h >> 16);
}

// Derives a 32-bit key from the state's seed. noise_state_t keeps its layout
// (it is mirrored by the Lua FFI cdef), so the key is recomputed per call;
// it is a handful of integer ops.
static inline unsigned int seed_key(const noise_state_t* s) {
    unsigned long long sm = s->seed;
    return (unsigned int)(splitmix64(&sm) >> 32);
}

static inline float to_range(unsigned int h) {
    return ((float)(h >> 8) / (float)0x00FFFFFF) * 2.0f - 1.0f;
}

} // namespace vnoise

extern "C" {

VNOISE_API float white2_eval(const noise_state_t* s, int ix, int iy) {
    if (!s) return 0;
    return vnoise::to_range(vnoise::hash4((unsigned int)ix, (unsigned int)iy, 0u, vnoise::seed_key(s)));
}

VNOISE_API float white3_eval(const noise_state_t* s, int ix, int iy, int iz) {
    if (!s) return 0;
    return vnoise::to_range(
        vnoise::hash4((unsigned int)ix, (unsigned int)iy, (unsigned int)iz, vnoise::seed_key(s)));
}

// Batch fill of seeded 2D white noise over integer cells: out[j * w + i] is
// white2_eval(s, ox + i, oy + j). The seed key is derived once per call, so
// each value costs one integer hash; the values are bit-identical to
// white2_eval at the same cell.
VNOISE_API void white2_fill_grid(const noise_state_t* s, float* out,
                                 int ox, int oy, int w, int h) {
    if (!s || !out || w <= 0 || h <= 0) return;
    const unsigned int key = vnoise::seed_key(s);
    for (int j = 0; j < h; ++j) {
        const unsigned int y = (unsigned int)(oy + j);
        for (int i = 0; i < w; ++i) {
            out[j * w + i] = vnoise::to_range(vnoise::hash4((unsigned int)(ox + i), y, 0u, key));
        }
    }
}

}
