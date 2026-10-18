#include "vnoise/internal.h"

// Absolute-cell sampling through a domain transform (see vnoise_domain_t).
// Every value is computed from the cell's absolute index alone, so blocks
// that overlap (chunks with an apron) agree on their shared cells.
// The fractal parameters come in a vnoise_sampler_t so that every argument
// is passed in a register (see the calling convention rule in vnoise.h).

namespace {

// Offsets of the warp field samples of level k > 0 (level 0 keeps the
// original (5.2, 1.3) and (1.7, 9.2), so one-level warps are unchanged).
inline float level_offset(int k, float base) {
    return base + 13.7f * (float)k;
}

// Displaces (cx, cy) by the domain's warp: one level (the original warp) or
// warp_levels iterated levels, each sampling the field at the point displaced
// by the previous one.
inline void warp_point(const noise_state_t* s, const vnoise_domain_t* d, float* cx, float* cy) {
    const float lac = d->warp_lac != 0.0f ? d->warp_lac : 2.0f;
    const float gain = d->warp_gain != 0.0f ? d->warp_gain : 0.5f;
    int levels = d->warp_levels;
    if (levels < 1) levels = 1;
    if (levels > VNOISE_MAX_WARP_LEVELS) levels = VNOISE_MAX_WARP_LEVELS;
    const float x0 = *cx, y0 = *cy;
    float qx = 0.0f, qy = 0.0f;
    for (int k = 0; k < levels; ++k) {
        const float px = k == 0 ? x0 : x0 + d->warp_amp * qx;
        const float py = k == 0 ? y0 : y0 + d->warp_amp * qy;
        const float wx = px * d->warp_freq;
        const float wy = py * d->warp_freq;
        const float ax = k == 0 ? 5.2f : level_offset(k, 5.2f);
        const float ay = k == 0 ? 1.3f : level_offset(k, 1.3f);
        const float bx = k == 0 ? 1.7f : level_offset(k, 1.7f);
        const float by = k == 0 ? 9.2f : level_offset(k, 9.2f);
        qx = vnoise::fbm_sample(s, d->warp_base, wx + ax, wy + ay, d->warp_octaves, lac, gain,
                                vnoise::FBM);
        qy = vnoise::fbm_sample(s, d->warp_base, wx + bx, wy + by, d->warp_octaves, lac, gain,
                                vnoise::FBM);
    }
    *cx = x0 + d->warp_amp * qx;
    *cy = y0 + d->warp_amp * qy;
}

} // namespace

extern "C" VNOISE_API void vnoise_fill_domain(const noise_state_t* s, const vnoise_sampler_t* sp,
                                              float* out, int c0, int r0, int w, int h,
                                              const vnoise_domain_t* d) {
    if (!s || !sp || !out || !d || w <= 0 || h <= 0) return;
    if (sp->mode < VNOISE_MODE_FBM || sp->mode > VNOISE_MODE_TURB) return;
    const int base = sp->base, mode = sp->mode, octaves = sp->octaves;
    const float lac = sp->lac, gain = sp->gain;
    const float* m = d->m;
    const bool warp = d->warp_amp != 0.0f;
    for (int j = 0; j < h; ++j) {
        const float r = (float)(r0 + j);
        for (int i = 0; i < w; ++i) {
            const float c = (float)(c0 + i);
            float cx = m[0] * c + m[1] * r + m[2];
            float cy = m[3] * c + m[4] * r + m[5];
            if (warp) warp_point(s, d, &cx, &cy);
            out[j * w + i] = vnoise::fbm_sample(s, base, d->ox + cx * d->freq, d->oy + cy * d->freq,
                                                octaves, lac, gain, mode);
        }
    }
}

namespace vnoise {

// Same mapping as the loop of vnoise_fill_domain, as a reusable function.
void domain_point(const noise_state_t* s, const vnoise_domain_t* d, float c, float r,
                  float* x, float* y) {
    const float* m = d->m;
    float cx = m[0] * c + m[1] * r + m[2];
    float cy = m[3] * c + m[4] * r + m[5];
    if (d->warp_amp != 0.0f) warp_point(s, d, &cx, &cy);
    *x = d->ox + cx * d->freq;
    *y = d->oy + cy * d->freq;
}

} // namespace vnoise
