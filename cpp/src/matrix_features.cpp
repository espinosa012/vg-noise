#include <cmath>
#include <vector>
#include "vnoise/internal.h"
#include "polyline.h"

// Positioned features on a finite matrix: point stamps (dome, cone, crater,
// mesa, basin) and features along a polyline (ridge, valley, escarpment).
// Only the feature's bounding box is visited; values written are clamped to
// 0..1.

namespace {

using vnoise::clamp01f;
using vnoise::smoothstepf;

const float DEG = 0.017453292519943295f;

// Blends a feature value v (with footprint weight wgt in 0..1) into m.
inline float blend(int mode, float m, float v, float wgt, float target) {
    switch (mode) {
    case VNOISE_BLEND_ADD: return m + v;
    case VNOISE_BLEND_SUB: return m - v;
    case VNOISE_BLEND_MAX: return v > m ? v : m;
    case VNOISE_BLEND_MIN: return v < m ? v : m;
    case VNOISE_BLEND_REPLACE: return m + wgt * (target - m);
    default: return m;
    }
}

// Stamp profiles in 0..1 at normalized distance d (0 center, 1 edge).
float stamp_profile(const vnoise_stamp_t* st, float d) {
    if (d >= 1.0f) return 0.0f;
    switch (st->shape) {
    case VNOISE_STAMP_DOME:
    case VNOISE_STAMP_BASIN: {
        const float q = 1.0f - d * d;
        return q * q;
    }
    case VNOISE_STAMP_CONE: {
        const float c = st->p[0];
        if (c > 0.0f && d < c) {
            // Crater: from 60% of the rim height at the center up to the rim.
            const float u = d / c;
            return (1.0f - c) * (0.6f + 0.4f * u * u);
        }
        return 1.0f - d;
    }
    case VNOISE_STAMP_CRATER: {
        const float rim = 1.0f - (st->p[0] > 0.0f ? st->p[0] : 0.3f);
        const float floor_h = st->p[1];
        if (d < rim) {
            const float u = smoothstepf(0.0f, rim, d);
            return floor_h + (1.0f - floor_h) * u * u * u;
        }
        return 1.0f - smoothstepf(rim, 1.0f, d);
    }
    case VNOISE_STAMP_MESA: {
        const float slope = st->p[0] > 0.0f ? st->p[0] : 0.3f;
        return 1.0f - smoothstepf(1.0f - slope, 1.0f, d);
    }
    default:
        return 0.0f;
    }
}

// fBm of a seeded state (3-4 octaves, simplex), in about -1..1.
inline float rough(const noise_state_t* s, float x, float y, int octaves) {
    return vnoise::fbm_sample(s, VNOISE_BASE_SIMPLEX2, x, y, octaves, 2.0f, 0.5f, vnoise::FBM);
}

} // namespace

extern "C" VNOISE_API void vnoise_stamp(float* m, int w, int h, const vnoise_stamp_t* st) {
    if (!m || !st || w <= 0 || h <= 0 || !(st->rx > 0.0f)) return;
    const float rx = st->rx;
    const float ry = st->ry > 0.0f ? st->ry : rx;
    const float rough_amp = clamp01f(st->roughness);
    noise_state_t ns;
    noise_init(&ns, st->seed);
    const float ca = cosf(st->angle * DEG), sa = sinf(st->angle * DEG);
    // Bounding box of the (perturbed) ellipse.
    const float R = fmaxf(rx, ry) * (1.0f + 0.3f * rough_amp) + 1.0f;
    int i0 = (int)floorf(st->cx - R), i1 = (int)ceilf(st->cx + R);
    int j0 = (int)floorf(st->cy - R), j1 = (int)ceilf(st->cy + R);
    if (i0 < 0) i0 = 0;
    if (j0 < 0) j0 = 0;
    if (i1 > w - 1) i1 = w - 1;
    if (j1 > h - 1) j1 = h - 1;
    const float rmean = 0.5f * (rx + ry);
    const float sign = st->shape == VNOISE_STAMP_BASIN ? -1.0f : 1.0f;
    for (int j = j0; j <= j1; ++j) {
        for (int i = i0; i <= i1; ++i) {
            const float dx = (float)i + 0.5f - st->cx, dy = (float)j + 0.5f - st->cy;
            const float u = (dx * ca + dy * sa) / rx;
            const float v = (-dx * sa + dy * ca) / ry;
            float d = sqrtf(u * u + v * v);
            if (rough_amp > 0.0f && d > 0.0f) {
                // Outline: radius scaled by noise sampled on a circle of the
                // polar angle, so the perturbation is continuous all around.
                const float th = atan2f(v, u);
                d /= 1.0f + rough_amp * 0.25f * rough(&ns, 1.7f * cosf(th) + 11.3f, 1.7f * sinf(th) + 7.1f, 3);
            }
            float p = stamp_profile(st, d);
            if (p <= 0.0f) continue;
            float val = st->height * p;
            if (rough_amp > 0.0f) {
                const float k = 3.0f / rmean;
                val *= 1.0f + rough_amp * 0.3f * rough(&ns, (float)i * k + 3.7f, (float)j * k + 1.9f, 4);
            }
            float& cell = m[j * w + i];
            cell = clamp01f(blend(st->blend, cell, sign * val, p, st->height));
        }
    }
}

extern "C" VNOISE_API void vnoise_path_feature(float* m, int w, int h, const float* points, int n,
                                               const vnoise_path_t* pf) {
    if (!m || !pf || !points || w <= 0 || h <= 0 || n < 2 || !(pf->width > 0.0f)) return;
    vnoise::Polyline line;
    for (int k = 0; k < n; ++k) {
        line.x.push_back(points[2 * k]);
        line.y.push_back(points[2 * k + 1]);
    }
    vnoise::chaikin_xy(line.x, line.y, 0, pf->smooth > 0 ? pf->smooth : 0);
    const float half = 0.5f * pf->width;
    const float rough_amp = clamp01f(pf->roughness);
    const float reach = pf->kind == VNOISE_PATH_ESCARPMENT
                            ? (pf->reach > 0.0f ? pf->reach : 4.0f * pf->width)
                            : half + fabsf(pf->spurs);
    line.build(reach + 1.0f);
    if (!(line.length > 0.0f)) return;
    noise_state_t ns;
    noise_init(&ns, pf->seed);
    const float taper = pf->taper < 0.0f ? 0.0f : (pf->taper > 0.5f ? 0.5f : pf->taper);
    const float sharp = pf->sharpness > 0.0f ? pf->sharpness : 1.0f;
    const float peak = clamp01f(pf->peakiness);
    const float fscale = 2.0f / pf->width;
    // Bounding box of the path grown by the reach.
    float x0 = 1e30f, y0 = 1e30f, x1 = -1e30f, y1 = -1e30f;
    for (size_t k = 0; k < line.x.size(); ++k) {
        x0 = fminf(x0, line.x[k]); y0 = fminf(y0, line.y[k]);
        x1 = fmaxf(x1, line.x[k]); y1 = fmaxf(y1, line.y[k]);
    }
    int i0 = (int)floorf(x0 - reach - 1.0f), i1 = (int)ceilf(x1 + reach + 1.0f);
    int j0 = (int)floorf(y0 - reach - 1.0f), j1 = (int)ceilf(y1 + reach + 1.0f);
    if (i0 < 0) i0 = 0;
    if (j0 < 0) j0 = 0;
    if (i1 > w - 1) i1 = w - 1;
    if (j1 > h - 1) j1 = h - 1;
    for (int j = j0; j <= j1; ++j) {
        for (int i = i0; i <= i1; ++i) {
            const float px = (float)i + 0.5f, py = (float)j + 0.5f;
            vnoise::Polyline::Hit hit;
            if (!line.nearest(px, py, &hit)) continue;
            float d = hit.d;
            if (pf->spurs != 0.0f && pf->kind != VNOISE_PATH_ESCARPMENT) {
                // Warping the distance makes the flanks branch into spurs.
                d += pf->spurs * rough(&ns, px * fscale + 5.3f, py * fscale + 2.1f, 3);
                if (d < 0.0f) d = 0.0f;
            }
            const float t = hit.arc / line.length;
            const float env = taper > 0.0f ? smoothstepf(0.0f, taper, t) * smoothstepf(0.0f, taper, 1.0f - t) : 1.0f;
            float wgt;
            if (pf->kind == VNOISE_PATH_ESCARPMENT) {
                if (hit.side * (pf->side < 0 ? -1 : 1) < 0) continue;
                wgt = env * smoothstepf(0.0f, pf->width, d) * (1.0f - smoothstepf(reach - pf->width, reach, d));
            } else {
                const float q = 1.0f - (d / half) * (d / half);
                if (q <= 0.0f) continue;
                wgt = env * powf(q, sharp);
            }
            if (wgt <= 0.0f) continue;
            float val = pf->height * wgt;
            if (pf->kind == VNOISE_PATH_RIDGE && peak > 0.0f) {
                // Ridged peaks along the crest: (1 - |n|)^2 fractal in 0..1.
                const float r = vnoise::fbm_sample(&ns, VNOISE_BASE_SIMPLEX2, px * fscale * 0.8f + 1.3f,
                                                   py * fscale * 0.8f + 8.7f, 4, 2.0f, 0.5f, vnoise::RIDGE);
                val *= (1.0f - peak) + peak * (0.25f + 0.75f * r);
            }
            if (rough_amp > 0.0f) {
                val *= 1.0f + rough_amp * 0.3f * rough(&ns, px * fscale * 2.0f + 4.4f, py * fscale * 2.0f + 6.6f, 4);
            }
            float& cell = m[j * w + i];
            cell = clamp01f(blend(pf->blend, cell, val, wgt, pf->height));
        }
    }
}
