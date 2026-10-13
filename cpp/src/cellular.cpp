#include <cmath>
#include "vnoise/internal.h"

// Cellular (Worley) noise: one feature point per integer lattice cell,
// jittered around the cell center from a hash of the cell and the seed.

namespace vnoise {

// Hash channels of a lattice cell: point x, point y, cell value.
static inline void feature_point(unsigned int key, int i, int j, float jitter,
                                 float* px, float* py) {
    const float u = hash_unit(hash4((unsigned int)i, (unsigned int)j, 11u, key));
    const float v = hash_unit(hash4((unsigned int)i, (unsigned int)j, 23u, key));
    *px = (float)i + 0.5f + jitter * (u - 0.5f);
    *py = (float)j + 0.5f + jitter * (v - 0.5f);
}

// Keeps the two smallest squared distances (strict comparisons, so ties go to
// the cell visited first) and the cell of the nearest one.
static inline void consider(float d2, int i, int j, float* d1, float* d2nd, int* ni, int* nj) {
    if (d2 < *d1) {
        *d2nd = *d1;
        *d1 = d2;
        *ni = i;
        *nj = j;
    } else if (d2 < *d2nd) {
        *d2nd = d2;
    }
}

float cellular2(const noise_state_t* s, float x, float y, float jitter, int ret) {
    if (!(jitter > 0.0f)) jitter = 0.0f; else if (jitter > 1.0f) jitter = 1.0f;
    const unsigned int key = seed_key(s);
    const int ci = (int)floorf(x);
    const int cj = (int)floorf(y);
    float d1 = 1e30f, d2 = 1e30f;
    int ni = ci, nj = cj;
    // The 3 x 3 neighborhood first, in a fixed order.
    for (int dj = -1; dj <= 1; ++dj) {
        for (int di = -1; di <= 1; ++di) {
            float px, py;
            feature_point(key, ci + di, cj + dj, jitter, &px, &py);
            const float ex = px - x, ey = py - y;
            consider(ex * ex + ey * ey, ci + di, cj + dj, &d1, &d2, &ni, &nj);
        }
    }
    // Then the ring at distance 2 (corners included), skipping cells that
    // cannot hold a point closer than the current second distance.
    const float fx = x - (float)ci, fy = y - (float)cj;
    for (int dj = -2; dj <= 2; ++dj) {
        for (int di = -2; di <= 2; ++di) {
            if (di > -2 && di < 2 && dj > -2 && dj < 2) continue;
            // Minimum distance from the point to the cell's square.
            const float gx = di < 0 ? fx - (float)(di + 1) : (di > 0 ? (float)di - fx : 0.0f);
            const float gy = dj < 0 ? fy - (float)(dj + 1) : (dj > 0 ? (float)dj - fy : 0.0f);
            if (gx * gx + gy * gy >= d2) continue;
            float px, py;
            feature_point(key, ci + di, cj + dj, jitter, &px, &py);
            const float ex = px - x, ey = py - y;
            consider(ex * ex + ey * ey, ci + di, cj + dj, &d1, &d2, &ni, &nj);
        }
    }
    float v;
    switch (ret) {
    case VNOISE_CELL_F1:
        v = sqrtf(d1);
        break;
    case VNOISE_CELL_F2:
        v = sqrtf(d2) * (1.0f / 1.5f);
        break;
    case VNOISE_CELL_EDGE:
        v = sqrtf(d2) - sqrtf(d1);
        break;
    case VNOISE_CELL_VALUE:
        return hash_unit(hash4((unsigned int)ni, (unsigned int)nj, 37u, key));
    default:
        return 0.0f;
    }
    if (!(v > 0.0f)) v = 0.0f; else if (v > 1.0f) v = 1.0f;
    return v;
}

float cellular_sample(const noise_state_t* s, float x, float y, int octaves,
                      float lac, float gain, float jitter, int ret) {
    if (!s || octaves <= 0) return 0.0f;
    octaves = clamp_octaves(octaves);
    float sum = 0.0f, amp = 1.0f, freq = 1.0f, norm = 0.0f;
    for (int o = 0; o < octaves; ++o) {
        const float n = cellular2(s, x * freq + octave_offset(o, 31.4159f),
                                  y * freq + octave_offset(o, 17.2207f), jitter, ret);
        sum += n * amp;
        norm += amp;
        amp *= gain;
        freq *= lac;
    }
    return norm > 0.0f ? sum / norm : 0.0f;
}

} // namespace vnoise

extern "C" VNOISE_API float cellular2_eval(const noise_state_t* s, float x, float y,
                                           float jitter, int ret) {
    if (!s) return 0.0f;
    return vnoise::cellular2(s, x, y, jitter, ret);
}
