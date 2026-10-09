#include "vnoise/internal.h"

namespace {

inline float clamp01f(float x) {
    return x < 0.0f ? 0.0f : (x > 1.0f ? 1.0f : x);
}

// Turns a signed inside distance (>= 0 inside, < 0 outside) into a weight.
inline float weight(bool inside, float d, float feather) {
    if (!inside) return 0.0f;
    if (feather <= 0.0f) return 1.0f;
    return clamp01f(d / feather);
}

// Distance from (x, y) to the segment (ax, ay)-(bx, by).
inline float segment_distance(float x, float y, float ax, float ay, float bx, float by) {
    const float ex = bx - ax, ey = by - ay;
    const float len2 = ex * ex + ey * ey;
    float t = len2 > 0.0f ? ((x - ax) * ex + (y - ay) * ey) / len2 : 0.0f;
    t = clamp01f(t);
    const float px = ax + t * ex - x, py = ay + t * ey - y;
    return sqrtf(px * px + py * py);
}

// Weight of a polygon of n vertices (x, y pairs in v) at (x, y): even-odd
// inside test; the feather distance is the distance to the nearest edge.
float polygon_weight(const float* v, int n, float x, float y, float feather) {
    bool inside = false;
    float best = 3.4e38f;
    for (int a = 0, b = n - 1; a < n; b = a++) {
        const float ax = v[2 * a], ay = v[2 * a + 1];
        const float bx = v[2 * b], by = v[2 * b + 1];
        if ((ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax) inside = !inside;
        if (feather > 0.0f) {
            const float dist = segment_distance(x, y, ax, ay, bx, by);
            if (dist < best) best = dist;
        }
    }
    return weight(inside, best, feather);
}

float mask_weight(const vnoise_mask_t* m, const float* data, float x, float y, float v) {
    const float* p = m->p;
    switch (m->type) {
    case VNOISE_MASK_RECT: {
        const float d = fminf(fminf(x - p[0], p[2] - x), fminf(y - p[1], p[3] - y));
        return weight(d >= 0.0f, d, m->feather);
    }
    case VNOISE_MASK_ELLIPSE: {
        if (p[2] <= 0.0f || p[3] <= 0.0f) return 0.0f;
        const float nx = (x - p[0]) / p[2], ny = (y - p[1]) / p[3];
        const float q = sqrtf(nx * nx + ny * ny);
        return weight(q <= 1.0f, (1.0f - q) * fminf(p[2], p[3]), m->feather);
    }
    case VNOISE_MASK_POLYGON: {
        const int n = (int)p[1];
        if (!data || n < 3) return 0.0f;
        return polygon_weight(data + (int)p[0], n, x, y, m->feather);
    }
    case VNOISE_MASK_RANGE: {
        const float d = fminf(v - p[0], p[1] - v);
        return weight(d >= 0.0f, d, m->feather);
    }
    default:
        return 0.0f;
    }
}

} // namespace

extern "C" VNOISE_API void vnoise_mask_blend(float* dst, int w, int h,
                                             const float* before, int before_stride,
                                             int c0, int r0, const vnoise_mask_t* mask,
                                             const float* data) {
    if (!dst || !before || !mask || w <= 0 || h <= 0) return;
    for (int j = 0; j < h; ++j) {
        const float y = (float)(r0 + j);
        for (int i = 0; i < w; ++i) {
            const float b = before[j * before_stride + i];
            float m = mask_weight(mask, data, (float)(c0 + i), y, b);
            if (mask->invert) m = 1.0f - m;
            float& o = dst[j * w + i];
            o = b + m * (o - b);
        }
    }
}
