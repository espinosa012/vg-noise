#include <cmath>
#include "vnoise/internal.h"

// Generic sampler entry point (vnoise_sampler_t) and the derivative-damped
// fBm mode.

namespace vnoise {

float base2_deriv(const noise_state_t* s, int base, float x, float y, float* dx, float* dy) {
    if (base == VNOISE_BASE_PERLIN2) return perlin2_deriv(s, x, y, dx, dy);
    return simplex2_grad(s, x, y, dx, dy);
}

// Quilez' "fBm with derivatives": the running sum D of amplitude-weighted
// gradients (this octave included) damps each octave by 1 / (1 + k |D|^2),
// so steep areas get less fine detail. Octave points match fbm_sample.
float damped_sample(const noise_state_t* s, int base, float x, float y,
                    int octaves, float lac, float gain, float damping) {
    if (!s || octaves <= 0) return 0.0f;
    float sum = 0.0f, amp = 1.0f, freq = 1.0f, norm = 0.0f;
    float Dx = 0.0f, Dy = 0.0f;
    for (int o = 0; o < octaves; ++o) {
        float gx, gy;
        const float n = base2_deriv(s, base, x * freq + octave_offset(o, 31.4159f),
                                    y * freq + octave_offset(o, 17.2207f), &gx, &gy);
        Dx += amp * gx;
        Dy += amp * gy;
        sum += amp * n / (1.0f + damping * (Dx * Dx + Dy * Dy));
        norm += amp;
        amp *= gain;
        freq *= lac;
    }
    return sum / norm;
}

static inline float sample(const noise_state_t* s, const vnoise_sampler_t* sp, float x, float y) {
    switch (sp->mode) {
    case VNOISE_MODE_FBM:
    case VNOISE_MODE_RIDGE:
    case VNOISE_MODE_TURB:
        return fbm_sample(s, sp->base, x, y, sp->octaves, sp->lac, sp->gain, sp->mode);
    case VNOISE_MODE_CELL_F1:
    case VNOISE_MODE_CELL_F2:
    case VNOISE_MODE_CELL_EDGE:
    case VNOISE_MODE_CELL_VALUE:
        return cellular_sample(s, x, y, sp->octaves, sp->lac, sp->gain, sp->jitter,
                               sp->mode - VNOISE_MODE_CELL_F1);
    case VNOISE_MODE_DAMPED:
        return damped_sample(s, sp->base, x, y, sp->octaves, sp->lac, sp->gain, sp->damping);
    default:
        return 0.0f;
    }
}

} // namespace vnoise

extern "C" VNOISE_API void vnoise_fill_sampler(const noise_state_t* s, const vnoise_sampler_t* sp,
                                               float* out, int c0, int r0, int w, int h,
                                               const vnoise_domain_t* d) {
    if (!s || !sp || !out || !d || w <= 0 || h <= 0) return;
    if (sp->mode < VNOISE_MODE_FBM || sp->mode > VNOISE_MODE_DAMPED) return;
    for (int j = 0; j < h; ++j) {
        const float r = (float)(r0 + j);
        for (int i = 0; i < w; ++i) {
            float x, y;
            vnoise::domain_point(s, d, (float)(c0 + i), r, &x, &y);
            out[j * w + i] = vnoise::sample(s, sp, x, y);
        }
    }
}
