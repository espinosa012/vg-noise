#include "vnoise/internal.h"

namespace vnoise {

static inline float base2(const noise_state_t* s, int base, float x, float y) {
    switch (base) {
        case VNOISE_BASE_PERLIN2:  return perlin2_eval(s, x, y);
        case VNOISE_BASE_SIMPLEX2: return simplex2(s, x, y);
        case VNOISE_BASE_WHITE2:   return white2_eval(s, (int)floorf(x), (int)floorf(y));
        default: return 0.0f;
    }
}

static inline float base3(const noise_state_t* s, int base,
                           float x, float y, float z) {
    switch (base) {
        case VNOISE_BASE_PERLIN3:  return perlin3_eval(s, x, y, z);
        case VNOISE_BASE_SIMPLEX3: return simplex3(s, x, y, z);
        case VNOISE_BASE_WHITE3:   return white3_eval(s, (int)floorf(x),
                                                      (int)floorf(y),
                                                      (int)floorf(z));
        default: return 0.0f;
    }
}

// Per-octave domain offset. Without it every octave samples the same field
// from the same origin, so with integer lacunarity the lattices of all
// octaves line up and the sum shows straight grid lines. The offsets are
// small irrational-ish steps, keeping float precision intact.
static inline float octave_offset(int o, float k) {
    return (float)o * k;
}

float fbm_sample(const noise_state_t* s, int base, float x, float y,
                 int octaves, float lac, float gain, int mode) {
    if (!s || octaves <= 0) return 0.0f;
    float sum = 0.0f;
    float amp = 1.0f;
    float freq = 1.0f;
    float norm = 0.0f;
    for (int o = 0; o < octaves; ++o) {
        float n = base2(s, base, x * freq + octave_offset(o, 31.4159f),
                        y * freq + octave_offset(o, 17.2207f));
        if (mode == RIDGE) {
            // Sharp crests where the base noise crosses zero: (1 - |n|)^2.
            n = 1.0f - fabsf(n);
            n *= n;
        }
        else if (mode == TURB) n = fabsf(n);
        sum += n * amp;
        norm += amp;
        amp *= gain;
        freq *= lac;
    }
    return sum / norm;
}

float fbm_sample3(const noise_state_t* s, int base, float x, float y, float z,
                  int octaves, float lac, float gain, int mode) {
    if (!s || octaves <= 0) return 0.0f;
    float sum = 0.0f;
    float amp = 1.0f;
    float freq = 1.0f;
    float norm = 0.0f;
    for (int o = 0; o < octaves; ++o) {
        float n = base3(s, base, x * freq + octave_offset(o, 31.4159f),
                        y * freq + octave_offset(o, 17.2207f),
                        z * freq + octave_offset(o, 23.9071f));
        if (mode == RIDGE) {
            // Sharp crests where the base noise crosses zero: (1 - |n|)^2.
            n = 1.0f - fabsf(n);
            n *= n;
        }
        else if (mode == TURB) n = fabsf(n);
        sum += n * amp;
        norm += amp;
        amp *= gain;
        freq *= lac;
    }
    return sum / norm;
}

} // namespace vnoise

extern "C" {

VNOISE_API float fbm2_eval(const noise_state_t* s, int base, float x, float y,
                           int octaves, float lac, float gain) {
    return vnoise::fbm_sample(s, base, x, y, octaves, lac, gain, vnoise::FBM);
}

VNOISE_API float fbm3_eval(const noise_state_t* s, int base, float x, float y, float z,
                           int octaves, float lac, float gain) {
    return vnoise::fbm_sample3(s, base, x, y, z, octaves, lac, gain, vnoise::FBM);
}

}