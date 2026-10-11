#ifndef VNOISE_POLYLINE_H
#define VNOISE_POLYLINE_H

#include <cmath>
#include <vector>

// Nearest-segment queries on a polyline with a uniform bucket index, shared by
// path features and river carving. Each segment is registered in every bucket
// its bounding box grown by `reach` overlaps, so a query at a point returns the
// nearest segment among those within `reach` of it.

namespace vnoise {

struct Polyline {
    std::vector<float> x, y;   // vertices
    std::vector<float> s;      // cumulative arc length at each vertex
    float length = 0.0f;
    float bucket = 1.0f;       // bucket size in cells
    float ox = 0.0f, oy = 0.0f; // bucket grid origin
    int bw = 0, bh = 0;
    std::vector<int> start, items;

    // Result of a query: distance, arc length at the projection, segment
    // index and parameter along it, and the side: +1 on the right of the
    // direction of travel as seen on screen (y down; south of an eastward
    // line), -1 on the left.
    struct Hit {
        float d, arc, t;
        int seg;
        int side;
    };

    void build(float reach) {
        const int n = (int)x.size();
        s.assign(n, 0.0f);
        for (int k = 1; k < n; ++k) {
            const float dx = x[k] - x[k - 1], dy = y[k] - y[k - 1];
            s[k] = s[k - 1] + sqrtf(dx * dx + dy * dy);
        }
        length = n > 0 ? s[n - 1] : 0.0f;
        float x0 = 1e30f, y0 = 1e30f, x1 = -1e30f, y1 = -1e30f;
        for (int k = 0; k < n; ++k) {
            x0 = fminf(x0, x[k]); y0 = fminf(y0, y[k]);
            x1 = fmaxf(x1, x[k]); y1 = fmaxf(y1, y[k]);
        }
        bucket = fmaxf(8.0f, reach);
        ox = x0 - reach - bucket;
        oy = y0 - reach - bucket;
        bw = (int)((x1 + reach + bucket - ox) / bucket) + 1;
        bh = (int)((y1 + reach + bucket - oy) / bucket) + 1;
        std::vector<int> counts(bw * bh + 1, 0);
        for (int pass = 0; pass < 2; ++pass) {
            std::vector<int> fill;
            if (pass == 1) {
                start.assign(bw * bh + 1, 0);
                for (int b = 0; b < bw * bh; ++b) start[b + 1] = start[b] + counts[b];
                items.assign(start[bw * bh], 0);
                fill.assign(start.begin(), start.end() - 1);
            }
            for (int k = 0; k + 1 < n; ++k) {
                const int bx0 = (int)((fminf(x[k], x[k + 1]) - reach - ox) / bucket);
                const int bx1 = (int)((fmaxf(x[k], x[k + 1]) + reach - ox) / bucket);
                const int by0 = (int)((fminf(y[k], y[k + 1]) - reach - oy) / bucket);
                const int by1 = (int)((fmaxf(y[k], y[k + 1]) + reach - oy) / bucket);
                for (int by = by0; by <= by1; ++by) {
                    for (int bx = bx0; bx <= bx1; ++bx) {
                        if (bx < 0 || by < 0 || bx >= bw || by >= bh) continue;
                        const int b = by * bw + bx;
                        if (pass == 0) counts[b]++;
                        else items[fill[b]++] = k;
                    }
                }
            }
        }
    }

    // Nearest segment to (px, py) among the indexed ones; false when none.
    bool nearest(float px, float py, Hit* hit) const {
        const int bx = (int)floorf((px - ox) / bucket);
        const int by = (int)floorf((py - oy) / bucket);
        if (bx < 0 || by < 0 || bx >= bw || by >= bh) return false;
        const int b = by * bw + bx;
        float best = 1e30f;
        bool found = false;
        for (int it = start[b]; it < start[b + 1]; ++it) {
            const int k = items[it];
            const float ax = x[k], ay = y[k];
            const float ex = x[k + 1] - ax, ey = y[k + 1] - ay;
            const float len2 = ex * ex + ey * ey;
            float t = len2 > 0.0f ? ((px - ax) * ex + (py - ay) * ey) / len2 : 0.0f;
            t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
            const float dx = ax + t * ex - px, dy = ay + t * ey - py;
            const float d2 = dx * dx + dy * dy;
            if (d2 < best) {
                best = d2;
                found = true;
                hit->seg = k;
                hit->t = t;
                hit->arc = s[k] + t * (s[k + 1] - s[k]);
                const float cross = ex * (py - ay) - ey * (px - ax);
                hit->side = cross >= 0.0f ? 1 : -1;
            }
        }
        if (found) hit->d = sqrtf(best);
        return found;
    }
};

// Chaikin corner cutting on x/y (and optional extra attributes), keeping ends.
inline void chaikin_xy(std::vector<float>& x, std::vector<float>& y, std::vector<float>* z, int passes) {
    for (int pass = 0; pass < passes; ++pass) {
        const size_t n = x.size();
        if (n < 3) return;
        std::vector<float> nx, ny, nz;
        nx.reserve(2 * n); ny.reserve(2 * n);
        nx.push_back(x[0]); ny.push_back(y[0]);
        if (z) nz.push_back((*z)[0]);
        for (size_t k = 0; k + 1 < n; ++k) {
            nx.push_back(0.75f * x[k] + 0.25f * x[k + 1]);
            ny.push_back(0.75f * y[k] + 0.25f * y[k + 1]);
            nx.push_back(0.25f * x[k] + 0.75f * x[k + 1]);
            ny.push_back(0.25f * y[k] + 0.75f * y[k + 1]);
            if (z) {
                nz.push_back(0.75f * (*z)[k] + 0.25f * (*z)[k + 1]);
                nz.push_back(0.25f * (*z)[k] + 0.75f * (*z)[k + 1]);
            }
        }
        nx.push_back(x[n - 1]); ny.push_back(y[n - 1]);
        if (z) nz.push_back((*z)[n - 1]);
        x.swap(nx); y.swap(ny);
        if (z) z->swap(nz);
    }
}

inline float smoothstepf(float e0, float e1, float v) {
    if (e1 <= e0) return v >= e0 ? 1.0f : 0.0f;
    float t = (v - e0) / (e1 - e0);
    t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
    return t * t * (3.0f - 2.0f * t);
}

inline float clamp01f(float v) {
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

} // namespace vnoise

#endif
