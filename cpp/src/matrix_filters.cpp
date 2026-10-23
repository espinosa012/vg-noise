#include <cmath>
#include <vector>
#include "vnoise/internal.h"
#include "hydrology.h"

// Matrix filters: stream-power erosion over the shared hydrology,
// resampling between matrix sizes, and Gaussian blurs of any width as
// successive extended box filters.

namespace {

inline float clamp01(float v) {
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

inline float catmull(float p0, float p1, float p2, float p3, float t) {
    return 0.5f * (2.0f * p1 + (p2 - p0) * t + (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t * t +
                   (3.0f * (p1 - p2) + p3 - p0) * t * t * t);
}

inline float at(const float* src, int sw, int sh, int i, int j) {
    i = i < 0 ? 0 : (i >= sw ? sw - 1 : i);
    j = j < 0 ? 0 : (j >= sh ? sh - 1 : j);
    return src[j * sw + i];
}

// One extended box filter (radius r, end weight alpha) over a line of n
// values, in place, its ends clamped. P (n + 1 prefix sums) and tmp (n
// values) are scratch. Each output is O(1): the clamped window splits into
// runs of the first value, a prefix-sum range and runs of the last value.
void box_line(float* line, int n, int r, double alpha, std::vector<double>& P, std::vector<float>& tmp) {
    P[0] = 0.0;
    for (int k = 0; k < n; ++k) {
        tmp[k] = line[k];
        P[k + 1] = P[k] + tmp[k];
    }
    const double first = tmp[0], last = tmp[n - 1];
    const double norm = 1.0 / (2.0 * r + 1.0 + 2.0 * alpha);
    for (int q = 0; q < n; ++q) {
        const long a = (long)q - r, b = (long)q + r;
        double sum = 0.0;
        if (a < 0) sum += first * (double)((b < 0 ? b : -1) - a + 1);
        if (b >= n) sum += last * (double)(b - (a > n ? a : n) + 1);
        const long lo = a < 0 ? 0 : a, hi = b >= n ? n - 1 : b;
        if (lo <= hi) sum += P[hi + 1] - P[lo];
        if (alpha > 0.0) {
            const long e0 = a - 1, e1 = b + 1;
            sum += alpha * (e0 < 0 ? first : (e0 >= n ? last : (double)tmp[e0]));
            sum += alpha * (e1 < 0 ? first : (e1 >= n ? last : (double)tmp[e1]));
        }
        line[q] = (float)(sum * norm);
    }
}

// Blurs every line of an axis (n values at `stride`, lines `step` apart):
// each line is extended by `pad` copies of its end values, so the boxes see
// the original clamped extension in every pass (the extension's far ends
// stay constant while pad covers the reach of all passes), filtered, and its
// middle written back.
void blur_axis(float* m, int lines, int step, int n, int stride, int passes, int r, double alpha,
               int pad, std::vector<float>& ext, std::vector<double>& P, std::vector<float>& tmp) {
    const int len = n + 2 * pad;
    for (int l = 0; l < lines; ++l) {
        float* line = m + (size_t)l * step;
        for (int t = 0; t < len; ++t) {
            const int k = t - pad;
            ext[t] = line[(size_t)(k < 0 ? 0 : (k >= n ? n - 1 : k)) * stride];
        }
        for (int p = 0; p < passes; ++p) box_line(ext.data(), len, r, alpha, P, tmp);
        for (int k = 0; k < n; ++k) line[(size_t)k * stride] = ext[k + pad];
    }
}

// Erodes a matrix that fits the node budget; writes heights and flow.
void erode_direct(float* m, int w, int h, const vnoise_erosion_t* ep, const float* uplift,
                  float* flow_out) {
    using namespace vnoise::hydro;
    const Grid g = { w, h, w * h };
    std::vector<double> H(g.n), U(g.n, 0.0), scratch;
    for (int k = 0; k < g.n; ++k) {
        H[k] = clamp01(m[k]);
        if (uplift) U[k] = (double)clamp01(uplift[k]) * ep->uplift_rate;
    }
    std::vector<unsigned char> outlet;
    mark_outlets(g, H, ep->sea_level, ep->outlets, outlet);
    const ErosionParams p = { ep->k, ep->dt, ep->diffusion };
    const int reroute = ep->reroute > 0 ? ep->reroute : 4;
    Drainage dr;
    for (int it = 0; it < ep->iterations; ++it) {
        if (it % reroute == 0) drain(g, ep->m, H, outlet, dr);
        erosion_step(g, p, U, dr, H, scratch, outlet);
    }
    for (int k = 0; k < g.n; ++k) m[k] = clamp01((float)H[k]);
    if (flow_out) {
        mark_outlets(g, H, ep->sea_level, ep->outlets, outlet);
        drain(g, ep->m, H, outlet, dr);
        double amax = 1.0;
        for (int k = 0; k < g.n; ++k) amax = dr.A[k] > amax ? dr.A[k] : amax;
        const double lmax = log(1.0 + amax);
        for (int k = 0; k < g.n; ++k) flow_out[k] = clamp01((float)(log(1.0 + dr.A[k]) / lmax));
    }
}

} // namespace

extern "C" VNOISE_API void vnoise_resample(const float* src, int sw, int sh, float* dst, int dw, int dh,
                                           int mode) {
    if (!src || !dst || sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
    const float fx = (float)sw / (float)dw, fy = (float)sh / (float)dh;
    for (int j = 0; j < dh; ++j) {
        float gy = ((float)j + 0.5f) * fy - 0.5f;
        if (gy < 0.0f) gy = 0.0f;
        if (gy > (float)(sh - 1)) gy = (float)(sh - 1);
        const int y = (int)floorf(gy);
        const float ty = gy - (float)y;
        for (int i = 0; i < dw; ++i) {
            float gx = ((float)i + 0.5f) * fx - 0.5f;
            if (gx < 0.0f) gx = 0.0f;
            if (gx > (float)(sw - 1)) gx = (float)(sw - 1);
            const int x = (int)floorf(gx);
            const float tx = gx - (float)x;
            const float a = at(src, sw, sh, x, y), b = at(src, sw, sh, x + 1, y);
            const float c = at(src, sw, sh, x, y + 1), d = at(src, sw, sh, x + 1, y + 1);
            float v;
            if (mode == VNOISE_RESAMPLE_BICUBIC) {
                float rows[4];
                for (int k = 0; k < 4; ++k) {
                    const int yy = y - 1 + k;
                    rows[k] = catmull(at(src, sw, sh, x - 1, yy), at(src, sw, sh, x, yy),
                                      at(src, sw, sh, x + 1, yy), at(src, sw, sh, x + 2, yy), tx);
                }
                v = catmull(rows[0], rows[1], rows[2], rows[3], ty);
                const float lo = fminf(fminf(a, b), fminf(c, d)), hi = fmaxf(fmaxf(a, b), fmaxf(c, d));
                v = v < lo ? lo : (v > hi ? hi : v);
            } else {
                const float top = a + tx * (b - a), bottom = c + tx * (d - c);
                v = top + ty * (bottom - top);
            }
            dst[j * dw + i] = v;
        }
    }
}

extern "C" VNOISE_API void vnoise_erode_matrix(float* m, int w, int h, const vnoise_erosion_t* ep,
                                               const float* uplift, float* flow_out) {
    if (!m || !ep || w <= 0 || h <= 0) return;
    if (ep->diffusion < 0.0f || ep->diffusion > 0.25f) return;
    long long budget = ep->max_cells > 0 ? ep->max_cells : 262144;
    if (budget > 1048576) budget = 1048576;
    if ((long long)w * h <= budget) {
        erode_direct(m, w, h, ep, uplift, flow_out);
        return;
    }
    // Erode a downsample within the budget and add the upsampled change, so
    // the original's small-scale detail survives where erosion changes little.
    const double f = sqrt((double)w * h / (double)budget);
    const int dw = (int)ceil(w / f), dh = (int)ceil(h / f);
    int sw = dw, sh = dh;
    while ((long long)sw * sh > budget) {
        sw = sw > 1 ? sw - 1 : 1;
        sh = sh > 1 ? sh - 1 : 1;
    }
    std::vector<float> low(sw * sh), before(sw * sh);
    vnoise_resample(m, w, h, low.data(), sw, sh, VNOISE_RESAMPLE_BILINEAR);
    before = low;
    std::vector<float> up_down;
    if (uplift) {
        up_down.resize(sw * sh);
        vnoise_resample(uplift, w, h, up_down.data(), sw, sh, VNOISE_RESAMPLE_BILINEAR);
    }
    std::vector<float> flow_low(flow_out ? sw * sh : 0);
    erode_direct(low.data(), sw, sh, ep, uplift ? up_down.data() : 0, flow_out ? flow_low.data() : 0);
    for (int k = 0; k < sw * sh; ++k) low[k] -= before[k];
    std::vector<float> delta(w * h);
    vnoise_resample(low.data(), sw, sh, delta.data(), w, h, VNOISE_RESAMPLE_BILINEAR);
    for (int k = 0; k < w * h; ++k) m[k] = clamp01(m[k] + delta[k]);
    if (flow_out) vnoise_resample(flow_low.data(), sw, sh, flow_out, w, h, VNOISE_RESAMPLE_BILINEAR);
}

extern "C" VNOISE_API void vnoise_blur_matrix(const float* src, int w, int h, float* dst,
                                              const vnoise_blur_t* bp) {
    if (!src || !dst || !bp || w <= 0 || h <= 0) return;
    const size_t n = (size_t)w * h;
    if (dst != src) {
        for (size_t k = 0; k < n; ++k) dst[k] = src[k];
    }
    const double sigma = bp->sigma > 16384.0f ? 16384.0 : bp->sigma;
    if (sigma > 0.0) {
        const int passes = bp->passes <= 0 ? 3 : (bp->passes > 8 ? 8 : bp->passes);
        // Every pass has variance sigma^2 / passes: the largest integer box
        // radius whose variance r (r + 1) / 3 does not exceed it, and the end
        // weight that makes up the difference exactly (0 <= alpha < 1).
        const double v = sigma * sigma / passes;
        const int r = (int)floor(0.5 * sqrt(12.0 * v + 1.0) - 0.5);
        const double rr = (double)r;
        const double alpha = (2.0 * rr + 1.0) * (rr * (rr + 1.0) / 3.0 - v) / (2.0 * (v - (rr + 1.0) * (rr + 1.0)));
        const int pad = passes * (r + 1) + 1;
        const int len = (w > h ? w : h) + 2 * pad;
        std::vector<float> ext(len), tmp(len);
        std::vector<double> P(len + 1);
        blur_axis(dst, h, w, w, 1, passes, r, alpha, pad, ext, P, tmp);
        blur_axis(dst, w, 1, h, w, passes, r, alpha, pad, ext, P, tmp);
    }
    for (size_t k = 0; k < n; ++k) dst[k] = clamp01(dst[k]);
}
