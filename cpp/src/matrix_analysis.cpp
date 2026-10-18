#include <cmath>
#include <vector>
#include "vnoise/internal.h"

// Matrix analysis and warping: coordinate warp by displacement matrices or a
// seeded warp field, exact Euclidean distance fields, and slope / aspect /
// curvature with Horn's gradient.

namespace {

const float PI = 3.14159265358979f;

inline float clamp01(float v) {
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

inline float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

inline float at(const float* m, int w, int h, int i, int j) {
    i = i < 0 ? 0 : (i >= w ? w - 1 : i);
    j = j < 0 ? 0 : (j >= h ? h - 1 : j);
    return m[j * w + i];
}

inline float catmull(float p0, float p1, float p2, float p3, float t) {
    return 0.5f * (2.0f * p1 + (p2 - p0) * t + (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t * t +
                   (3.0f * (p1 - p2) + p3 - p0) * t * t * t);
}

// Samples m at index-space point (x, y) (cell (i, j) at (i, j)) with clamped
// edges: bilinear, or Catmull-Rom clamped to the 2 x 2 neighborhood.
float sample(const float* m, int w, int h, float x, float y, int filter) {
    x = clampf(x, 0.0f, (float)(w - 1));
    y = clampf(y, 0.0f, (float)(h - 1));
    const int i = (int)floorf(x), j = (int)floorf(y);
    const float tx = x - (float)i, ty = y - (float)j;
    const float a = at(m, w, h, i, j), b = at(m, w, h, i + 1, j);
    const float c = at(m, w, h, i, j + 1), d = at(m, w, h, i + 1, j + 1);
    if (filter == VNOISE_SAMPLE_BICUBIC) {
        float rows[4];
        for (int k = 0; k < 4; ++k) {
            const int jj = j - 1 + k;
            rows[k] = catmull(at(m, w, h, i - 1, jj), at(m, w, h, i, jj), at(m, w, h, i + 1, jj),
                              at(m, w, h, i + 2, jj), tx);
        }
        const float v = catmull(rows[0], rows[1], rows[2], rows[3], ty);
        const float lo = fminf(fminf(a, b), fminf(c, d)), hi = fmaxf(fmaxf(a, b), fmaxf(c, d));
        return clampf(v, lo, hi);
    }
    const float top = a + tx * (b - a), bottom = c + tx * (d - c);
    return top + ty * (bottom - top);
}

// Felzenszwalb-Huttenlocher 1D squared distance transform of f (n values)
// into d, with scratch arrays v (int, n) and z (n + 1).
void dt1d(const double* f, int n, double* d, int* v, double* z) {
    const double INF = 1e30;
    int k = 0;
    v[0] = 0;
    z[0] = -INF;
    z[1] = INF;
    for (int q = 1; q < n; ++q) {
        double s;
        for (;;) {
            const int p = v[k];
            s = ((f[q] + (double)q * q) - (f[p] + (double)p * p)) / (2.0 * (q - p));
            if (s > z[k]) break;
            --k;  // z[0] is -INF, so k never goes below 0
        }
        ++k;
        v[k] = q;
        z[k] = s;
        z[k + 1] = INF;
    }
    k = 0;
    for (int q = 0; q < n; ++q) {
        while (z[k + 1] < (double)q) ++k;
        const double dq = (double)(q - v[k]);
        d[q] = dq * dq + f[v[k]];
    }
}

// Exact squared Euclidean distance from every cell of a (w + 2p) x (h + 2p)
// grid to the nearest target (target[k] != 0); 1e30-ish where there is none.
void edt(const std::vector<unsigned char>& target, int gw, int gh, std::vector<double>& out) {
    const double INF = 1e20;
    out.assign((size_t)gw * gh, INF);
    for (size_t k = 0; k < out.size(); ++k) out[k] = target[k] ? 0.0 : INF;
    const int n = gw > gh ? gw : gh;
    std::vector<double> f(n), d(n), z(n + 1);
    std::vector<int> v(n);
    for (int i = 0; i < gw; ++i) {
        for (int j = 0; j < gh; ++j) f[j] = out[(size_t)j * gw + i];
        dt1d(f.data(), gh, d.data(), v.data(), z.data());
        for (int j = 0; j < gh; ++j) out[(size_t)j * gw + i] = d[j];
    }
    for (int j = 0; j < gh; ++j) {
        double* row = &out[(size_t)j * gw];
        for (int i = 0; i < gw; ++i) f[i] = row[i];
        dt1d(f.data(), gw, d.data(), v.data(), z.data());
        for (int i = 0; i < gw; ++i) row[i] = d[i];
    }
}

} // namespace

extern "C" VNOISE_API void vnoise_warp_matrix(const float* src, int w, int h, float* dst,
                                              const float* dx, const float* dy,
                                              const float* strength, const vnoise_warp_t* wp) {
    if (!src || !dst || !wp || w <= 0 || h <= 0 || src == dst) return;
    const float amp = wp->amp;
    for (int j = 0; j < h; ++j) {
        for (int i = 0; i < w; ++i) {
            const int k = j * w + i;
            float ux = 0.0f, uy = 0.0f;
            if (dx && dy) {
                ux = 2.0f * (dx[k] - 0.5f);
                uy = 2.0f * (dy[k] - 0.5f);
            } else if (dx) {
                const float a = 2.0f * PI * dx[k];
                const float s = strength ? strength[k] : 1.0f;
                ux = cosf(a) * s;
                uy = sinf(a) * s;
            }
            dst[k] = clamp01(sample(src, w, h, (float)i + amp * ux, (float)j + amp * uy, wp->filter));
        }
    }
}

extern "C" VNOISE_API void vnoise_warp_matrix_noise(const float* src, int w, int h, float* dst,
                                                    const noise_state_t* s, const vnoise_warp_t* wp) {
    if (!src || !dst || !wp || !s || w <= 0 || h <= 0 || src == dst) return;
    // The warp field of a domain transform with an identity affine: cell
    // (i, j) is displaced exactly as vnoise_fill_domain would displace it.
    vnoise_domain_t d;
    d.m[0] = 1.0f; d.m[1] = 0.0f; d.m[2] = 0.0f;
    d.m[3] = 0.0f; d.m[4] = 1.0f; d.m[5] = 0.0f;
    d.ox = 0.0f; d.oy = 0.0f; d.freq = 1.0f;
    d.warp_amp = wp->amp;
    d.warp_freq = wp->freq;
    d.warp_octaves = wp->octaves > 0 ? wp->octaves : 3;
    d.warp_base = wp->base;
    d.warp_levels = wp->levels;
    d.warp_lac = wp->lac;
    d.warp_gain = wp->gain;
    for (int j = 0; j < h; ++j) {
        for (int i = 0; i < w; ++i) {
            float x = (float)i, y = (float)j;
            if (wp->amp != 0.0f) vnoise::domain_point(s, &d, (float)i, (float)j, &x, &y);
            dst[j * w + i] = clamp01(sample(src, w, h, x, y, wp->filter));
        }
    }
}

extern "C" VNOISE_API void vnoise_distance_field(const float* m, int w, int h, float* out,
                                                 const vnoise_distance_t* dp) {
    if (!m || !out || !dp || w <= 0 || h <= 0) return;
    const int mode = dp->mode;
    const int pad = dp->edge == VNOISE_EDGE_NONE ? 0 : 1;
    const int gw = w + 2 * pad, gh = h + 2 * pad;
    const bool edge_above = dp->edge == VNOISE_EDGE_ABOVE;
    const bool edge_below = dp->edge == VNOISE_EDGE_BELOW;
    // above[k]: the grid cell is in the set m >= threshold; below[k]: it is
    // not. Padding cells belong to the set the edge mode names (or neither).
    std::vector<unsigned char> above((size_t)gw * gh, 0), below((size_t)gw * gh, 0);
    bool any_above = false, any_below = false;
    for (int j = 0; j < gh; ++j) {
        for (int i = 0; i < gw; ++i) {
            const size_t g = (size_t)j * gw + i;
            const int mi = i - pad, mj = j - pad;
            if (mi < 0 || mj < 0 || mi >= w || mj >= h) {
                above[g] = edge_above ? 1 : 0;
                below[g] = edge_below ? 1 : 0;
            } else {
                const bool a = m[mj * w + mi] >= dp->threshold;
                above[g] = a ? 1 : 0;
                below[g] = a ? 0 : 1;
            }
            any_above = any_above || above[g];
            any_below = any_below || below[g];
        }
    }
    std::vector<double> d_out, d_in;
    if (mode != VNOISE_DIST_INSIDE) edt(above, gw, gh, d_out);
    if (mode != VNOISE_DIST_OUTSIDE) edt(below, gw, gh, d_in);
    // Signed or plain distance per matrix cell (in cells), before scaling.
    std::vector<float> raw((size_t)w * h);
    float maxd = 0.0f;
    for (int j = 0; j < h; ++j) {
        for (int i = 0; i < w; ++i) {
            const size_t g = (size_t)(j + pad) * gw + (i + pad);
            const bool a = m[j * w + i] >= dp->threshold;
            float v;
            if (mode == VNOISE_DIST_OUTSIDE) {
                v = any_above ? (float)sqrt(d_out[g]) : -1.0f;
            } else if (mode == VNOISE_DIST_INSIDE) {
                v = any_below ? (float)sqrt(d_in[g]) : -1.0f;
            } else if (a) {
                v = any_below ? (float)sqrt(d_in[g]) - 0.5f : 1e30f;
            } else {
                v = any_above ? -((float)sqrt(d_out[g]) - 0.5f) : -1e30f;
            }
            raw[j * w + i] = v;
            const float mag = fabsf(v);
            if (mag < 1e29f && mag > maxd) maxd = mag;
        }
    }
    const float range = dp->range > 0.0f ? dp->range : (maxd > 0.0f ? maxd : 1.0f);
    for (int k = 0; k < w * h; ++k) {
        const float v = raw[k];
        if (mode == VNOISE_DIST_SIGNED) {
            out[k] = 0.5f + 0.5f * clampf(v / range, -1.0f, 1.0f);
        } else {
            out[k] = v < 0.0f ? 1.0f : clamp01(v / range);
        }
    }
}

extern "C" VNOISE_API void vnoise_slope(const float* m, int w, int h, float* out,
                                        const vnoise_slope_t* sp) {
    if (!m || !out || !sp || w <= 0 || h <= 0 || m == out) return;
    const float Z = sp->relief * (float)(w > h ? w : h);
    const float range = sp->range > 0.0f ? sp->range : 1.0f;
    for (int j = 0; j < h; ++j) {
        for (int i = 0; i < w; ++i) {
            float v;
            if (sp->mode == VNOISE_SLOPE_CURVATURE) {
                const float c = m[j * w + i];
                const float lap = at(m, w, h, i - 1, j) + at(m, w, h, i + 1, j) + at(m, w, h, i, j - 1) +
                                  at(m, w, h, i, j + 1) - 4.0f * c;
                v = 0.5f + 0.5f * clampf(lap * Z / range, -1.0f, 1.0f);
            } else {
                const float z1 = at(m, w, h, i - 1, j - 1), z2 = at(m, w, h, i, j - 1),
                            z3 = at(m, w, h, i + 1, j - 1);
                const float z4 = at(m, w, h, i - 1, j), z6 = at(m, w, h, i + 1, j);
                const float z7 = at(m, w, h, i - 1, j + 1), z8 = at(m, w, h, i, j + 1),
                            z9 = at(m, w, h, i + 1, j + 1);
                const float gx = ((z3 + 2.0f * z6 + z9) - (z1 + 2.0f * z4 + z7)) * 0.125f;
                const float gy = ((z7 + 2.0f * z8 + z9) - (z1 + 2.0f * z2 + z3)) * 0.125f;
                const float g = sqrtf(gx * gx + gy * gy) * Z;
                switch (sp->mode) {
                case VNOISE_SLOPE_GRADIENT:
                    v = clamp01(g / range);
                    break;
                case VNOISE_SLOPE_ASPECT:
                    if (gx == 0.0f && gy == 0.0f) {
                        v = 0.0f;
                    } else {
                        float a = atan2f(-gy, -gx) / (2.0f * PI);
                        v = a < 0.0f ? a + 1.0f : a;
                        if (v >= 1.0f) v = 0.0f;
                    }
                    break;
                case VNOISE_SLOPE_DX:
                    v = 0.5f + 0.5f * clampf(gx * Z / range, -1.0f, 1.0f);
                    break;
                case VNOISE_SLOPE_DY:
                    v = 0.5f + 0.5f * clampf(gy * Z / range, -1.0f, 1.0f);
                    break;
                default:
                    v = atanf(g) / (0.5f * PI);
                    break;
                }
            }
            out[j * w + i] = v;
        }
    }
}
