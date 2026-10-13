#include <cmath>
#include "terrain_plan.h"

// Per-block evaluation of a terrain plan: every output of a cell depends only
// on the cell's absolute index and the plan, so blocks tile seamlessly.

namespace {

inline float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

inline float smoothstep(float e0, float e1, float x) {
    if (e1 <= e0) return x >= e0 ? 1.0f : 0.0f;
    const float t = clampf((x - e0) / (e1 - e0), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

// Position of a cell in the macro grid: base node index (so that i + 1 is a
// node too) and fraction, with coordinates clamped to the grid.
inline void macro_coord(float cell, int mc, int nodes, int* i, float* t) {
    float g = cell / (float)mc;
    g = clampf(g, 0.0f, (float)(nodes - 1));
    int k = (int)floorf(g);
    if (k > nodes - 2) k = nodes - 2;
    *i = k;
    *t = g - (float)k;
}

inline float node(const std::vector<float>& grid, int mw, int mh, int i, int j) {
    i = i < 0 ? 0 : (i >= mw ? mw - 1 : i);
    j = j < 0 ? 0 : (j >= mh ? mh - 1 : j);
    return grid[j * mw + i];
}

inline float catmull(float p0, float p1, float p2, float p3, float t) {
    return 0.5f * (2.0f * p1 + (p2 - p0) * t + (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t * t +
                   (3.0f * (p1 - p2) + p3 - p0) * t * t * t);
}

// Catmull-Rom over the 4 x 4 nodes around the cell, clamped to the range of
// the 2 x 2 nodes that enclose it (no overshoot, stays in 0..1).
float macro_height(const vnoise_plan* plan, int i, int j, float tx, float ty) {
    const std::vector<float>& H = plan->height;
    const int mw = plan->mw, mh = plan->mh;
    float rows[4];
    for (int k = 0; k < 4; ++k) {
        const int jj = j - 1 + k;
        rows[k] = catmull(node(H, mw, mh, i - 1, jj), node(H, mw, mh, i, jj),
                          node(H, mw, mh, i + 1, jj), node(H, mw, mh, i + 2, jj), tx);
    }
    const float v = catmull(rows[0], rows[1], rows[2], rows[3], ty);
    const float a = node(H, mw, mh, i, j), b = node(H, mw, mh, i + 1, j);
    const float c = node(H, mw, mh, i, j + 1), d = node(H, mw, mh, i + 1, j + 1);
    const float lo = fminf(fminf(a, b), fminf(c, d));
    const float hi = fmaxf(fmaxf(a, b), fmaxf(c, d));
    return clampf(v, lo, hi);
}

float bilinear(const std::vector<float>& grid, int mw, int mh, int i, int j, float tx, float ty) {
    const float a = node(grid, mw, mh, i, j), b = node(grid, mw, mh, i + 1, j);
    const float c = node(grid, mw, mh, i, j + 1), d = node(grid, mw, mh, i + 1, j + 1);
    const float top = a + tx * (b - a), bottom = c + tx * (d - c);
    return top + ty * (bottom - top);
}

} // namespace

extern "C" VNOISE_API void vnoise_plan_fill(const vnoise_plan_t* plan, int c0, int r0, int w, int h,
                                            const float* detail, const vnoise_terrain_out_t* out) {
    if (!plan || !out || w <= 0 || h <= 0) return;
    float* elevation = out->elevation;
    float* river = out->river;
    float* lake = out->lake;
    float* flow = out->flow;
    float* channel_distance = out->channel_distance;
    const vnoise_plan_params_t& p = plan->p;
    const int mw = plan->mw, mh = plan->mh;
    const float log_max = logf(1.0f + plan->flow_max);
    const bool need_height = elevation || lake;
    for (int j = 0; j < h; ++j) {
        const float r = (float)(r0 + j);
        int gj;
        float ty;
        macro_coord(r, p.macro_cell, mh, &gj, &ty);
        for (int i = 0; i < w; ++i) {
            const int k = j * w + i;
            const float c = (float)(c0 + i);
            int gi;
            float tx;
            macro_coord(c, p.macro_cell, mw, &gi, &tx);

            vnoise::RiverHit hit;
            const bool found = vnoise::plan_query(plan, c, r, &hit);
            const float half = found ? 0.5f * hit.width : 0.0f;
            const float s = found ? smoothstep(half, half + vnoise::valley_half_width(p, hit.width), hit.d)
                                  : 1.0f;

            float hgt = 0.0f;
            if (need_height) {
                hgt = macro_height(plan, gi, gj, tx, ty);
                if (detail) {
                    const float n = clampf(detail[k], -1.0f, 1.0f);
                    const float a = p.detail_amplitude * (1.0f - p.detail_valley_damping * (1.0f - s));
                    hgt += n * fminf(a, fminf(hgt, 1.0f - hgt));
                }
                if (found && hgt > hit.bed) {
                    const float profile = s >= 1.0f ? 1.0f : (s <= 0.0f ? 0.0f : powf(s, p.valley_shape));
                    hgt = hit.bed + (hgt - hit.bed) * profile;
                }
                hgt = clampf(hgt, 0.0f, 1.0f);
            }
            if (elevation) elevation[k] = hgt;
            if (river) {
                float v = 0.0f;
                if (found) {
                    if (hit.d <= half) v = 1.0f;
                    else if (hit.d < half + p.bank) v = 1.0f - (hit.d - half) / p.bank;
                }
                river[k] = v;
            }
            if (lake) {
                const float L = bilinear(plan->lake, mw, mh, gi, gj, tx, ty);
                const float surface = bilinear(plan->filled, mw, mh, gi, gj, tx, ty);
                lake[k] = hgt < surface ? smoothstep(0.25f, 0.75f, L) : 0.0f;
            }
            if (flow) {
                float v = logf(1.0f + bilinear(plan->flow, mw, mh, gi, gj, tx, ty)) / log_max;
                if (found && hit.d <= half) {
                    const float rv = logf(1.0f + hit.flow) / log_max;
                    if (rv > v) v = rv;
                }
                flow[k] = clampf(v, 0.0f, 1.0f);
            }
            if (channel_distance) {
                channel_distance[k] = found ? fminf(hit.d, p.distance_range) / p.distance_range : 1.0f;
            }
        }
    }
}
