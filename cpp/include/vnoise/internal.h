#ifndef VNOISE_INTERNAL_H
#define VNOISE_INTERNAL_H

#include <cmath>
#include "vnoise/vnoise.h"

namespace vnoise {

inline unsigned long long splitmix64(unsigned long long* state) {
    unsigned long long z = (state[0] += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

inline unsigned int xorshift32(unsigned int* state) {
    unsigned int x = state[0];
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state[0] = x;
    return x;
}

inline float fade(float t) {
    return t * t * t * (t * (t * 6.0f - 15.0f) + 10.0f);
}

inline float lerp(float a, float b, float t) {
    return a + t * (b - a);
}

float grad2(int hash, float x, float y);
float grad3(int hash, float x, float y, float z);

float simplex2(const noise_state_t* s, float x, float y);
float simplex3(const noise_state_t* s, float x, float y, float z);

float fbm_sample(const noise_state_t* s, int base, float x, float y,
                 int octaves, float lac, float gain, int mode);
float fbm_sample3(const noise_state_t* s, int base, float x, float y, float z,
                  int octaves, float lac, float gain, int mode);

enum FractalMode { FBM = 0, RIDGE = 1, TURB = 2 };

void seed_rng(unsigned long long seed, unsigned long long* sm,
              unsigned int* xs);

// Applies an op chain to one value (see VNOISE_OP_* in vnoise.h). Ops run in
// order on unclamped values; only the final result is clamped when asked.
inline float apply_ops(float v, const vnoise_op_t* ops, int n, int clamp01) {
    for (int k = 0; k < n; ++k) {
        const vnoise_op_t& o = ops[k];
        switch (o.op) {
        case VNOISE_OP_REMAP: {
            float range = o.p[1] - o.p[0];
            // A zero range would give inf/NaN (undefined under -ffast-math).
            // Multiplying by the reciprocal matches the lo/hi image fill
            // bit for bit.
            v = range != 0.0f ? (v - o.p[0]) * (1.0f / range) : 0.0f;
            break;
        }
        case VNOISE_OP_SCALE:
            v = v * o.p[0];
            break;
        case VNOISE_OP_OFFSET:
            v = v + o.p[0];
            break;
        case VNOISE_OP_CONTRAST:
            v = (v - o.p[1]) * o.p[0] + o.p[1];
            break;
        default:
            break;
        }
    }
    if (clamp01) {
        if (v < 0.0f) v = 0.0f; else if (v > 1.0f) v = 1.0f;
    }
    return v;
}

} // namespace vnoise

#endif