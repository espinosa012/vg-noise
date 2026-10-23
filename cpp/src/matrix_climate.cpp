#include <cmath>
#include <vector>
#include "vnoise/internal.h"

// Moisture carried by the wind over a height matrix: evaporation over the
// sources, orographic precipitation on the slopes that face the wind, and
// the distance travelled over land since the last source. The steady state
// is solved upwind with Gauss-Seidel sweeps ordered by wind quadrant.

namespace {

const float PI = 3.14159265358979f;
const float UNREACHED = 1e30f;

inline float clamp01(float v) {
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

// Upwind stencil of one cell: the wind ray crosses the previous column (x
// dominant) or row at a point between the primary neighbor p and the
// secondary neighbor s (weight frac), one step of L cells upwind.
struct Upwind {
    int p, s;          // neighbor indices, -1 outside the matrix
    float frac;        // weight of s
    float L;           // step length in cells
    float gain;        // moisture picked up over the step
    float rate;        // fraction of the moisture rained out (0 at sea)
    unsigned char quad; // wind quadrant: bit 0 x toward -x, bit 1 toward -y
    unsigned char source; // src >= 0.5: the fetch restarts here
};

// Wind of row j from the latitude bands: easterlies (trades and polar)
// toward -x and the equator, westerlies toward +x and the pole.
void band_wind(const vnoise_moisture_t* mp, int j, int h, float* ux, float* uy) {
    const float t = ((float)j + 0.5f) / (float)h;
    const float* b = mp->bands;
    const bool easterly = t < b[0] || (t >= b[1] && t < b[3]) || t >= b[4];
    // The equator lies at larger rows in the first hemisphere: equatorward is +y.
    const float toward_equator = t < b[2] ? 1.0f : -1.0f;
    const float a = mp->tilt * PI / 180.0f;
    if (easterly) {
        *ux = -cosf(a);
        *uy = sinf(a) * toward_equator;
    } else {
        *ux = cosf(a);
        *uy = -sinf(a) * toward_equator;
    }
}

} // namespace

extern "C" VNOISE_API void vnoise_moisture(const float* m, int w, int h, const vnoise_moisture_t* mp,
                                           const float* src, const float* dir,
                                           const vnoise_moisture_out_t* out) {
    if (!m || !mp || !out || w <= 0 || h <= 0) return;
    const int n = w * h;
    const float sea = mp->sea_level;
    const float cap = mp->capacity > 0.0f ? mp->capacity : 1.0f;
    const float inflow = mp->inflow < 0.0f ? 0.0f : (mp->inflow > cap ? cap : mp->inflow);
    const float Z = mp->relief * (float)(w > h ? w : h);
    const int cycles = mp->iterations <= 0 ? 4 : (mp->iterations > 256 ? 256 : mp->iterations);
    auto height = [m, sea](int k) {
        const float v = clamp01(m[k]);
        return v < sea ? sea : v;
    };

    // Stencils, gains and rain rates depend only on the inputs: computed once.
    std::vector<Upwind> up(n);
    for (int j = 0; j < h; ++j) {
        float bx = 1.0f, by = 0.0f;
        if (!dir) band_wind(mp, j, h, &bx, &by);
        for (int i = 0; i < w; ++i) {
            const int k = j * w + i;
            float ux = bx, uy = by;
            if (dir) {
                const float a = 2.0f * PI * dir[k];
                ux = cosf(a);
                uy = sinf(a);
            }
            const float ax = fabsf(ux), ay = fabsf(uy);
            const int sx = ux < 0.0f ? -1 : 1, sy = uy < 0.0f ? -1 : 1;
            Upwind& u = up[k];
            u.quad = (unsigned char)((sx < 0 ? 1 : 0) | (sy < 0 ? 2 : 0));
            int pi, pj;
            if (ax >= ay) {
                pi = i - sx;
                pj = j;
                u.frac = ay / ax;
                u.L = 1.0f / ax;
            } else {
                pi = i;
                pj = j - sy;
                u.frac = ax / ay;
                u.L = 1.0f / ay;
            }
            const int si = i - sx, sj = j - sy;
            const bool p_in = pi >= 0 && pj >= 0 && pi < w && pj < h;
            const bool s_in = si >= 0 && sj >= 0 && si < w && sj < h;
            u.p = p_in ? pj * w + pi : -1;
            u.s = s_in ? sj * w + si : -1;
            // Heights outside the matrix repeat the edge (no rise there).
            const int cpi = pi < 0 ? 0 : (pi >= w ? w - 1 : pi), cpj = pj < 0 ? 0 : (pj >= h ? h - 1 : pj);
            const int csi = si < 0 ? 0 : (si >= w ? w - 1 : si), csj = sj < 0 ? 0 : (sj >= h ? h - 1 : sj);
            const float hp = height(cpj * w + cpi), hs = height(csj * w + csi);
            const float h_up = hp + u.frac * (hs - hp);
            const float raw = clamp01(m[k]);
            const float s = src ? clamp01(src[k]) : (raw < sea ? 1.0f : 0.0f);
            u.gain = mp->evaporation * s * u.L;
            u.source = s >= 0.5f ? 1 : 0;
            if (raw >= sea) {
                const float rise = (height(k) - h_up) * Z;
                u.rate = clamp01(mp->base_rate * u.L + mp->orographic * (rise > 0.0f ? rise : 0.0f));
            } else {
                u.rate = 0.0f;
            }
        }
    }

    // Gauss-Seidel sweeps: in the sweep of a quadrant, rows and columns run
    // with the wind, so both upwind neighbors of its cells are already
    // updated; a uniform wind settles in its first sweep.
    std::vector<float> q(n, 0.0f), P(n, 0.0f);
    std::vector<float> f(out->fetch ? n : 0, UNREACHED);
    const float f_out = inflow > 0.0f ? 0.0f : UNREACHED;
    for (int c = 0; c < cycles; ++c) {
        for (int quad = 0; quad < 4; ++quad) {
            const int sx = (quad & 1) ? -1 : 1, sy = (quad & 2) ? -1 : 1;
            for (int jj = 0; jj < h; ++jj) {
                const int j = sy > 0 ? jj : h - 1 - jj;
                for (int ii = 0; ii < w; ++ii) {
                    const int i = sx > 0 ? ii : w - 1 - ii;
                    const int k = j * w + i;
                    const Upwind& u = up[k];
                    if (u.quad != quad) continue;
                    const float qp = u.p >= 0 ? q[u.p] : inflow;
                    const float qs = u.s >= 0 ? q[u.s] : inflow;
                    float v = qp + u.frac * (qs - qp) + u.gain;
                    v = v > cap ? cap : v;
                    const float rain = v * u.rate;
                    P[k] = rain;
                    q[k] = v - rain;
                    if (!f.empty()) {
                        if (u.source) {
                            f[k] = 0.0f;
                        } else {
                            // A side without a source upwind is left out of
                            // the interpolation.
                            const float fp = u.p >= 0 ? f[u.p] : f_out;
                            const float fs = u.s >= 0 ? f[u.s] : f_out;
                            float d;
                            if (fp >= UNREACHED && (fs >= UNREACHED || u.frac <= 0.0f)) d = UNREACHED;
                            else if (fp >= UNREACHED) d = fs;
                            else if (fs >= UNREACHED || u.frac <= 0.0f) d = fp;
                            else d = fp + u.frac * (fs - fp);
                            f[k] = d >= UNREACHED ? UNREACHED : d + u.L;
                        }
                    }
                }
            }
        }
    }

    if (out->precip) {
        float pmax = 0.0f;
        for (int k = 0; k < n; ++k) pmax = P[k] > pmax ? P[k] : pmax;
        const float range = mp->range > 0.0f ? mp->range : pmax;
        for (int k = 0; k < n; ++k) out->precip[k] = range > 0.0f ? clamp01(P[k] / range) : 0.0f;
    }
    if (out->moisture) {
        for (int k = 0; k < n; ++k) out->moisture[k] = clamp01(q[k] / cap);
    }
    if (out->fetch) {
        float fmax = 0.0f;
        for (int k = 0; k < n; ++k) {
            if (f[k] < UNREACHED && f[k] > fmax) fmax = f[k];
        }
        const float range = mp->fetch_range > 0.0f ? mp->fetch_range : fmax;
        for (int k = 0; k < n; ++k) {
            if (f[k] >= UNREACHED) out->fetch[k] = 1.0f;
            else out->fetch[k] = range > 0.0f ? clamp01(f[k] / range) : 0.0f;
        }
    }
}
