#include <algorithm>
#include <cstdlib>
#include <cstring>
#include "vnoise/internal.h"

// Valid-mode neighborhood kernels (see vnoise.h): an sw x sh input gives an
// (sw - 2R) x (sh - 2R) output, output (i, j) <-> input (i + R, j + R). No
// border policy is needed because nothing outside the input is read; callers
// that need full-size results sample an apron around their block.

namespace {

// Output size of a valid-mode pass with border radius r; false when empty.
inline bool valid_size(int sw, int sh, int r, int* ow, int* oh) {
    if (r < 0) return false;
    *ow = sw - 2 * r;
    *oh = sh - 2 * r;
    return *ow > 0 && *oh > 0;
}

float* alloc_floats(int n) {
    return (float*)std::malloc(sizeof(float) * (size_t)(n > 0 ? n : 1));
}

// Horizontal-only valid pass: (sw x sh) -> ((sw - 2r) x sh).
void row_pass(const float* src, int sw, int sh, float* dst, const float* k, int r) {
    const int ow = sw - 2 * r;
    const int taps = 2 * r + 1;
    for (int j = 0; j < sh; ++j) {
        const float* row = src + j * sw;
        float* out = dst + j * ow;
        for (int i = 0; i < ow; ++i) {
            float acc = 0.0f;
            for (int t = 0; t < taps; ++t) acc += k[t] * row[i + t];
            out[i] = acc;
        }
    }
}

// Vertical-only valid pass: (sw x sh) -> (sw x (sh - 2r)).
void col_pass(const float* src, int sw, int sh, float* dst, const float* k, int r) {
    const int oh = sh - 2 * r;
    const int taps = 2 * r + 1;
    for (int j = 0; j < oh; ++j) {
        float* out = dst + j * sw;
        for (int i = 0; i < sw; ++i) out[i] = 0.0f;
        for (int t = 0; t < taps; ++t) {
            const float kt = k[t];
            const float* row = src + (j + t) * sw;
            for (int i = 0; i < sw; ++i) out[i] += kt * row[i];
        }
    }
}

// Separable min (is_max = false) or max filter over a square, valid mode.
void minmax_square(const float* src, int sw, int sh, float* dst, int r, bool is_max) {
    const int ow = sw - 2 * r, oh = sh - 2 * r;
    float* tmp = alloc_floats(ow * sh);
    if (!tmp) return;
    for (int j = 0; j < sh; ++j) {
        const float* row = src + j * sw;
        for (int i = 0; i < ow; ++i) {
            float v = row[i];
            for (int t = 1; t <= 2 * r; ++t) v = is_max ? fmaxf(v, row[i + t]) : fminf(v, row[i + t]);
            tmp[j * ow + i] = v;
        }
    }
    for (int j = 0; j < oh; ++j) {
        for (int i = 0; i < ow; ++i) {
            float v = tmp[j * ow + i];
            for (int t = 1; t <= 2 * r; ++t) {
                const float u = tmp[(j + t) * ow + i];
                v = is_max ? fmaxf(v, u) : fminf(v, u);
            }
            dst[j * ow + i] = v;
        }
    }
    std::free(tmp);
}

// Min or max filter over a disc (dx^2 + dy^2 <= r^2), valid mode.
void minmax_disc(const float* src, int sw, int sh, float* dst, int r, bool is_max) {
    const int ow = sw - 2 * r, oh = sh - 2 * r;
    // Horizontal half-width of the disc on each row offset.
    int* half = (int*)std::malloc(sizeof(int) * (size_t)(2 * r + 1));
    if (!half) return;
    for (int dy = -r; dy <= r; ++dy) {
        int hw = 0;
        while ((hw + 1) * (hw + 1) + dy * dy <= r * r) ++hw;
        half[dy + r] = hw;
    }
    for (int j = 0; j < oh; ++j) {
        for (int i = 0; i < ow; ++i) {
            float v = src[(j + r) * sw + i + r];
            for (int dy = -r; dy <= r; ++dy) {
                const float* row = src + (j + r + dy) * sw + i + r;
                const int hw = half[dy + r];
                for (int dx = -hw; dx <= hw; ++dx) v = is_max ? fmaxf(v, row[dx]) : fminf(v, row[dx]);
            }
            dst[j * ow + i] = v;
        }
    }
    std::free(half);
}

void minmax(const float* src, int sw, int sh, float* dst, int r, bool is_max, int shape) {
    if (r == 0) {
        std::memcpy(dst, src, sizeof(float) * (size_t)sw * (size_t)sh);
        return;
    }
    if (shape == VNOISE_SHAPE_DISC) minmax_disc(src, sw, sh, dst, r, is_max);
    else minmax_square(src, sw, sh, dst, r, is_max);
}

} // namespace

extern "C" VNOISE_API void vnoise_convolve(const float* src, int sw, int sh, float* dst,
                                           const float* kernel, int r) {
    int ow, oh;
    if (!src || !dst || !kernel || !valid_size(sw, sh, r, &ow, &oh)) return;
    const int taps = 2 * r + 1;
    for (int j = 0; j < oh; ++j) {
        for (int i = 0; i < ow; ++i) {
            float acc = 0.0f;
            for (int a = 0; a < taps; ++a) {
                const float* row = src + (j + a) * sw + i;
                const float* krow = kernel + a * taps;
                for (int b = 0; b < taps; ++b) acc += krow[b] * row[b];
            }
            dst[j * ow + i] = acc;
        }
    }
}

extern "C" VNOISE_API void vnoise_convolve_sep(const float* src, int sw, int sh, float* dst,
                                               const float* kx, const float* ky, int r) {
    int ow, oh;
    if (!src || !dst || !kx || !ky || !valid_size(sw, sh, r, &ow, &oh)) return;
    float* tmp = alloc_floats(ow * sh);
    if (!tmp) return;
    row_pass(src, sw, sh, tmp, kx, r);
    col_pass(tmp, ow, sh, dst, ky, r);
    std::free(tmp);
}

extern "C" VNOISE_API void vnoise_sobel(const float* src, int sw, int sh, float* dst,
                                        int mode, float k) {
    int ow, oh;
    if (!src || !dst || !valid_size(sw, sh, 1, &ow, &oh)) return;
    for (int j = 0; j < oh; ++j) {
        const float* a = src + j * sw;        // row above the center
        const float* b = a + sw;              // center row
        const float* c = b + sw;              // row below
        for (int i = 0; i < ow; ++i) {
            const float gx = ((a[i + 2] - a[i]) + 2.0f * (b[i + 2] - b[i]) + (c[i + 2] - c[i])) * 0.25f;
            const float gy = ((c[i] - a[i]) + 2.0f * (c[i + 1] - a[i + 1]) + (c[i + 2] - a[i + 2])) * 0.25f;
            float v;
            if (mode == VNOISE_SOBEL_X) v = gx;
            else if (mode == VNOISE_SOBEL_Y) v = gy;
            else v = sqrtf(gx * gx + gy * gy);
            dst[j * ow + i] = k * v;
        }
    }
}

extern "C" VNOISE_API int vnoise_morph_radius(int op, int r) {
    if (r < 0) return 0;
    switch (op) {
    case VNOISE_MORPH_OPEN:
    case VNOISE_MORPH_CLOSE:
    case VNOISE_MORPH_TOPHAT:
    case VNOISE_MORPH_BLACKHAT:
        return 2 * r;
    default:
        return r;
    }
}

extern "C" VNOISE_API void vnoise_morph(const float* src, int sw, int sh, float* dst,
                                        int op, int r, int shape) {
    int ow, oh;
    if (!src || !dst || r < 0 || !valid_size(sw, sh, vnoise_morph_radius(op, r), &ow, &oh)) return;
    switch (op) {
    case VNOISE_MORPH_ERODE:
        minmax(src, sw, sh, dst, r, false, shape);
        return;
    case VNOISE_MORPH_DILATE:
        minmax(src, sw, sh, dst, r, true, shape);
        return;
    case VNOISE_MORPH_GRADIENT: {
        float* lo = alloc_floats(ow * oh);
        if (!lo) return;
        minmax(src, sw, sh, dst, r, true, shape);
        minmax(src, sw, sh, lo, r, false, shape);
        for (int n = 0; n < ow * oh; ++n) dst[n] -= lo[n];
        std::free(lo);
        return;
    }
    case VNOISE_MORPH_OPEN:
    case VNOISE_MORPH_CLOSE:
    case VNOISE_MORPH_TOPHAT:
    case VNOISE_MORPH_BLACKHAT: {
        // First pass shrinks by r, the second by r again.
        const bool first_max = op == VNOISE_MORPH_CLOSE || op == VNOISE_MORPH_BLACKHAT;
        const int mw = sw - 2 * r, mh = sh - 2 * r;
        float* mid = alloc_floats(mw * mh);
        if (!mid) return;
        minmax(src, sw, sh, mid, r, first_max, shape);
        minmax(mid, mw, mh, dst, r, !first_max, shape);
        std::free(mid);
        if (op == VNOISE_MORPH_TOPHAT || op == VNOISE_MORPH_BLACKHAT) {
            const int R = 2 * r;
            for (int j = 0; j < oh; ++j) {
                const float* row = src + (j + R) * sw + R;
                for (int i = 0; i < ow; ++i) {
                    float& o = dst[j * ow + i];
                    o = op == VNOISE_MORPH_TOPHAT ? row[i] - o : o - row[i];
                }
            }
        }
        return;
    }
    default:
        // Unknown op: plain crop, so the output is still well defined.
        for (int j = 0; j < oh; ++j)
            std::memcpy(dst + j * ow, src + (j + r) * sw + r, sizeof(float) * (size_t)ow);
        return;
    }
}

extern "C" VNOISE_API void vnoise_median(const float* src, int sw, int sh, float* dst, int r) {
    int ow, oh;
    if (!src || !dst || !valid_size(sw, sh, r, &ow, &oh)) return;
    const int taps = 2 * r + 1;
    const int count = taps * taps;
    float* win = alloc_floats(count);
    if (!win) return;
    for (int j = 0; j < oh; ++j) {
        for (int i = 0; i < ow; ++i) {
            int n = 0;
            for (int a = 0; a < taps; ++a) {
                const float* row = src + (j + a) * sw + i;
                for (int b = 0; b < taps; ++b) win[n++] = row[b];
            }
            std::nth_element(win, win + count / 2, win + count);
            dst[j * ow + i] = win[count / 2];
        }
    }
    std::free(win);
}

extern "C" VNOISE_API void vnoise_distance(const float* src, int sw, int sh, float* dst,
                                           int r, float t) {
    int ow, oh;
    if (!src || !dst || r <= 0 || !valid_size(sw, sh, r, &ow, &oh)) return;
    // Disc offsets sorted by distance, so the first hit is the nearest.
    const int side = 2 * r + 1;
    int* off = (int*)std::malloc(sizeof(int) * (size_t)side * (size_t)side);
    float* dist = alloc_floats(side * side);
    if (!off || !dist) {
        std::free(off);
        std::free(dist);
        return;
    }
    int n = 0;
    for (int dy = -r; dy <= r; ++dy) {
        for (int dx = -r; dx <= r; ++dx) {
            const int d2 = dx * dx + dy * dy;
            if (d2 > r * r) continue;
            off[n] = dy * sw + dx;
            dist[n] = sqrtf((float)d2);
            ++n;
        }
    }
    // Insertion sort by distance (n is at most a few thousand, sorted once).
    for (int a = 1; a < n; ++a) {
        const int o = off[a];
        const float d = dist[a];
        int b = a - 1;
        while (b >= 0 && dist[b] > d) {
            off[b + 1] = off[b];
            dist[b + 1] = dist[b];
            --b;
        }
        off[b + 1] = o;
        dist[b + 1] = d;
    }
    const float inv = 1.0f / (float)r;
    for (int j = 0; j < oh; ++j) {
        for (int i = 0; i < ow; ++i) {
            const float* center = src + (j + r) * sw + i + r;
            float v = 1.0f;
            for (int k = 0; k < n; ++k) {
                if (center[off[k]] >= t) {
                    v = dist[k] * inv;
                    break;
                }
            }
            dst[j * ow + i] = v;
        }
    }
    std::free(off);
    std::free(dist);
}
