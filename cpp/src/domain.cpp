#include "vnoise/internal.h"

// Absolute-cell sampling through a domain transform (see vnoise_domain_t).
// Every value is computed from the cell's absolute index alone, so blocks
// that overlap (chunks with an apron) agree on their shared cells.
extern "C" VNOISE_API void vnoise_fill_domain(const noise_state_t* s, int base, int mode,
                                              float* out, int c0, int r0, int w, int h,
                                              const vnoise_domain_t* d,
                                              int octaves, float lac, float gain) {
    if (!s || !out || !d || w <= 0 || h <= 0) return;
    const float* m = d->m;
    const bool warp = d->warp_amp != 0.0f;
    for (int j = 0; j < h; ++j) {
        const float r = (float)(r0 + j);
        for (int i = 0; i < w; ++i) {
            const float c = (float)(c0 + i);
            float cx = m[0] * c + m[1] * r + m[2];
            float cy = m[3] * c + m[4] * r + m[5];
            if (warp) {
                const float wx = cx * d->warp_freq;
                const float wy = cy * d->warp_freq;
                const float dx = vnoise::fbm_sample(s, d->warp_base, wx + 5.2f, wy + 1.3f,
                                                    d->warp_octaves, 2.0f, 0.5f, vnoise::FBM);
                const float dy = vnoise::fbm_sample(s, d->warp_base, wx + 1.7f, wy + 9.2f,
                                                    d->warp_octaves, 2.0f, 0.5f, vnoise::FBM);
                cx += d->warp_amp * dx;
                cy += d->warp_amp * dy;
            }
            out[j * w + i] = vnoise::fbm_sample(s, base, d->ox + cx * d->freq, d->oy + cy * d->freq,
                                                octaves, lac, gain, mode);
        }
    }
}
