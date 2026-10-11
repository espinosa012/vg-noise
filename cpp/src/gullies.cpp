#include <cmath>
#include "vnoise/internal.h"

// Analytic gullies erosion filter (in the spirit of the "erosion noise"
// technique): stripes aligned with the downhill direction of the input,
// evaluated by absolute cell so blocks tile. Radius 1 (central differences).

namespace vnoise {

static const float TWO_PI = 6.283185307179586f;
// Weight support in lattice cells. Feature points stay within the central
// half of their cell, so only the 3 x 3 lattice cells around the point can
// lie closer than this.
static const float GULLY_RADIUS = 1.25f;

// Average of cos(2 pi dot(x - q, dir)) over the lattice points q near p
// (lattice units), weighted by (1 - (d / R)^2)^2.
static inline float gully_octave(unsigned int key, int octave, float px, float py,
                                 float dirx, float diry) {
    const int ci = (int)floorf(px);
    const int cj = (int)floorf(py);
    float sum = 0.0f, wsum = 0.0f;
    for (int dj = -1; dj <= 1; ++dj) {
        for (int di = -1; di <= 1; ++di) {
            const unsigned int i = (unsigned int)(ci + di), j = (unsigned int)(cj + dj);
            const unsigned int z = 101u + 2u * (unsigned int)octave;
            const float qx = (float)(ci + di) + 0.25f + 0.5f * hash_unit(hash4(i, j, z, key));
            const float qy = (float)(cj + dj) + 0.25f + 0.5f * hash_unit(hash4(i, j, z + 1u, key));
            const float ex = px - qx, ey = py - qy;
            const float q = (ex * ex + ey * ey) * (1.0f / (GULLY_RADIUS * GULLY_RADIUS));
            if (q >= 1.0f) continue;
            const float w = (1.0f - q) * (1.0f - q);
            sum += w * cosf(TWO_PI * (ex * dirx + ey * diry));
            wsum += w;
        }
    }
    return wsum > 0.0f ? sum / wsum : 0.0f;
}

} // namespace vnoise

extern "C" VNOISE_API void vnoise_gullies(const float* src, int sw, int sh, float* dst,
                                          int c0, int r0, const noise_state_t* s,
                                          float scale, float strength, int octaves,
                                          float gain, float sharpness) {
    if (!src || !dst || !s || sw < 3 || sh < 3 || !(scale > 0.0f) || octaves <= 0) return;
    const int w = sw - 2, h = sh - 2;
    const unsigned int key = vnoise::seed_key(s);
    for (int j = 0; j < h; ++j) {
        for (int i = 0; i < w; ++i) {
            const float* p = src + (j + 1) * sw + (i + 1);
            const float v = *p;
            const float gx = 0.5f * (p[1] - p[-1]);
            const float gy = 0.5f * (p[sw] - p[-sw]);
            const float g2 = gx * gx + gy * gy;
            if (!(g2 > 0.0f)) {
                dst[j * w + i] = v;
                continue;
            }
            const float g = sqrtf(g2);
            // Unit vector perpendicular to the gradient: the phase varies
            // across the slope, so the stripes run downhill.
            const float dirx = -gy / g, diry = gx / g;
            const float cx = (float)(c0 + i + 1), cy = (float)(r0 + j + 1);
            float sum = 0.0f, norm = 0.0f, amp = 1.0f, spacing = scale;
            for (int o = 0; o < octaves; ++o) {
                sum += amp * vnoise::gully_octave(key, o, cx / spacing, cy / spacing, dirx, diry);
                norm += amp;
                amp *= gain;
                spacing *= 0.5f;
            }
            float slope = sharpness * g * scale;
            if (slope > 1.0f) slope = 1.0f;
            dst[j * w + i] = v + strength * slope * (norm > 0.0f ? sum / norm : 0.0f);
        }
    }
}
