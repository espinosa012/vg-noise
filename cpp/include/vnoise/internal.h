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

// Integer hash of the cell coordinates mixed with a per-seed key, so each
// seed yields an independent white-noise field.
inline unsigned int hash4(unsigned int x, unsigned int y, unsigned int z, unsigned int k) {
    unsigned int h = x * 374761393u + y * 668265263u + z * 2147483647u + k * 3266489917u;
    h = (h ^ (h >> 13)) * 1274126177u;
    return h ^ (h >> 16);
}

// Derives a 32-bit key from the state's seed. noise_state_t keeps its layout
// (it is mirrored by the Lua FFI cdef), so the key is recomputed per call;
// it is a handful of integer ops.
inline unsigned int seed_key(const noise_state_t* s) {
    unsigned long long sm = s->seed;
    return (unsigned int)(splitmix64(&sm) >> 32);
}

// Maps a hash to [0, 1) with 24 bits of precision.
inline float hash_unit(unsigned int h) {
    return (float)(h >> 8) * (1.0f / 16777216.0f);
}

// Maps absolute cell (c, r) through a domain (affine, then optional fBm warp)
// to the noise sample point. Shared by vnoise_fill_domain and
// vnoise_fill_sampler so both give bit-identical points.
void domain_point(const noise_state_t* s, const vnoise_domain_t* d, float c, float r,
                  float* x, float* y);

// Per-octave domain offset shared by every fractal sum (see fbm.cpp).
inline float octave_offset(int o, float k) {
    return (float)o * k;
}

float grad2(int hash, float x, float y);
float grad3(int hash, float x, float y, float z);

float simplex2(const noise_state_t* s, float x, float y);
float simplex2_grad(const noise_state_t* s, float x, float y, float* gx, float* gy);
float simplex3(const noise_state_t* s, float x, float y, float z);

float fbm_sample(const noise_state_t* s, int base, float x, float y,
                 int octaves, float lac, float gain, int mode);
float fbm_sample3(const noise_state_t* s, int base, float x, float y, float z,
                  int octaves, float lac, float gain, int mode);

enum FractalMode { FBM = 0, RIDGE = 1, TURB = 2 };

// 2D base noise with its analytic gradient (Perlin or Simplex; any other base
// falls back to Simplex).
float base2_deriv(const noise_state_t* s, int base, float x, float y, float* dx, float* dy);

// Derivative-damped fBm (see VNOISE_MODE_DAMPED).
float damped_sample(const noise_state_t* s, int base, float x, float y,
                    int octaves, float lac, float gain, float damping);

// Cellular noise of one octave and its fractal sum (see VNOISE_MODE_CELL_*).
float cellular2(const noise_state_t* s, float x, float y, float jitter, int ret);
float cellular_sample(const noise_state_t* s, float x, float y, int octaves,
                      float lac, float gain, float jitter, int ret);

void seed_rng(unsigned long long seed, unsigned long long* sm,
              unsigned int* xs);

// Applies an op chain to one value (see VNOISE_OP_* in vnoise.h). Ops run in
// order on unclamped values; only the final result is clamped when asked.
inline float apply_ops(float v, const vnoise_op_t* ops, int n, const float* data,
                       int clamp01) {
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
        case VNOISE_OP_LUT: {
            if (!data) break;
            int count = (int)o.p[1];
            if (count < 1) break;
            const float* t = data + (int)o.p[0];
            if (count == 1) {
                v = t[0];
                break;
            }
            // Clamp to [0, 1]; the negated test also sends NaN to 0.
            float x = v;
            if (!(x > 0.0f)) x = 0.0f; else if (x > 1.0f) x = 1.0f;
            float f = x * (float)(count - 1);
            int i = (int)f;
            if (i > count - 2) i = count - 2;
            v = t[i] + (t[i + 1] - t[i]) * (f - (float)i);
            break;
        }
        case VNOISE_OP_INVERT:
            v = 1.0f - v;
            break;
        case VNOISE_OP_THRESHOLD:
            v = v >= o.p[0] ? 1.0f : 0.0f;
            break;
        case VNOISE_OP_SMOOTHSTEP: {
            float range = o.p[1] - o.p[0];
            if (range == 0.0f) {
                v = v >= o.p[0] ? 1.0f : 0.0f;
                break;
            }
            float t = (v - o.p[0]) / range;
            if (!(t > 0.0f)) t = 0.0f; else if (t > 1.0f) t = 1.0f;
            v = t * t * (3.0f - 2.0f * t);
            break;
        }
        case VNOISE_OP_GAMMA:
            v = v > 0.0f ? powf(v, o.p[0]) : 0.0f;
            break;
        case VNOISE_OP_QUANTIZE: {
            float n = floorf(o.p[0]);
            if (!(n >= 2.0f)) break;
            float x = v;
            if (!(x > 0.0f)) x = 0.0f; else if (x > 1.0f) x = 1.0f;
            float q = floorf(x * n);
            if (q > n - 1.0f) q = n - 1.0f;
            v = q / (n - 1.0f);
            break;
        }
        case VNOISE_OP_CLAMP:
            if (v < o.p[0]) v = o.p[0];
            if (v > o.p[1]) v = o.p[1];
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