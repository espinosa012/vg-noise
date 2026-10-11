#include <cmath>
#include <queue>
#include <utility>
#include <vector>
#include "vnoise/internal.h"
#include "polyline.h"

// Rivers on a finite matrix: tracing from a source down the steepest descent
// with bounded breaching of pits, carving a channel whose bed never rises
// downstream, and seeded selection of random sources.

namespace {

using vnoise::clamp01f;
using vnoise::smoothstepf;

const int DX[8] = { 1, -1, 0, 0, 1, -1, 1, -1 };
const int DY[8] = { 0, 0, 1, -1, 1, 1, -1, -1 };
const float DIST[8] = { 1, 1, 1, 1, 1.41421356f, 1.41421356f, 1.41421356f, 1.41421356f };

// Outcome of breaching a pit.
enum Breach { BREACH_FOUND, BREACH_LAKE };

// Bounded priority-flood from the pit `start` inside a (2R + 1)^2 window:
// cells are popped lowest first; the first popped cell lower than the pit, on
// the edge, below sea level or on an existing channel ends the search, and the
// back-pointers give the spill path. If the window is exhausted, the popped
// cells below the lowest border cell (the spill level) form a lake.
Breach breach(const float* hgt, int w, int h, int start, int R, float sea, const float* mask,
              std::vector<int>& path_out, std::vector<int>& lake_out) {
    const int sx = start % w, sy = start / w;
    const int side = 2 * R + 1;
    std::vector<int> parent(side * side, -2);  // -2 unseen, -1 root
    std::vector<unsigned char> popped(side * side, 0);
    typedef std::pair<float, int> Item;  // (height, window index)
    std::priority_queue<Item, std::vector<Item>, std::greater<Item> > open;
    auto win = [&](int x, int y) { return (y - sy + R) * side + (x - sx + R); };
    const float pit = hgt[start];
    parent[win(sx, sy)] = -1;
    open.push(Item(pit, win(sx, sy)));
    lake_out.clear();
    while (!open.empty()) {
        const int wi = open.top().second;
        open.pop();
        if (popped[wi]) continue;
        popped[wi] = 1;
        const int x = wi % side - R + sx, y = wi / side - R + sy;
        const int idx = y * w + x;
        const bool edge = x == 0 || y == 0 || x == w - 1 || y == h - 1;
        const bool done = idx != start && (hgt[idx] < pit || hgt[idx] < sea || edge || (mask && mask[idx] >= 0.75f));
        if (done) {
            path_out.clear();
            for (int c = wi; c >= 0; c = parent[c]) {
                const int cx = c % side - R + sx, cy = c / side - R + sy;
                path_out.push_back(cy * w + cx);
            }
            // From the pit (exclusive) to the exit.
            path_out.pop_back();
            std::vector<int> fwd(path_out.rbegin(), path_out.rend());
            path_out.swap(fwd);
            return BREACH_FOUND;
        }
        lake_out.push_back(idx);
        for (int k = 0; k < 8; ++k) {
            const int nx = x + DX[k], ny = y + DY[k];
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (nx < sx - R || nx > sx + R || ny < sy - R || ny > sy + R) continue;
            const int nw = win(nx, ny);
            if (parent[nw] != -2) continue;
            parent[nw] = wi;
            open.push(Item(hgt[ny * w + nx], nw));
        }
    }
    // The window is exhausted without an exit: the water rises to the lowest
    // cell reached on the window's border (where it would spill next), and
    // only the popped cells below that level form the lake, not the whole
    // window.
    float level = 1e30f;
    for (size_t k = 0; k < lake_out.size(); ++k) {
        const int x = lake_out[k] % w, y = lake_out[k] / w;
        if (x == sx - R || x == sx + R || y == sy - R || y == sy + R) {
            if (hgt[lake_out[k]] < level) level = hgt[lake_out[k]];
        }
    }
    std::vector<int> below;
    for (size_t k = 0; k < lake_out.size(); ++k) {
        if (hgt[lake_out[k]] < level) below.push_back(lake_out[k]);
    }
    lake_out.swap(below);
    return BREACH_LAKE;
}

// splitmix64-based uniform float in [0, 1).
inline float next_unit(unsigned long long* st) {
    return (float)(vnoise::splitmix64(st) >> 40) * (1.0f / 16777216.0f);
}

} // namespace

extern "C" VNOISE_API int vnoise_river(float* height, int w, int h, float sx, float sy,
                                       const vnoise_river_t* rp, float* mask,
                                       float* out_points, int max_points) {
    if (!height || !rp || w <= 0 || h <= 0) return 0;
    const int ci = (int)floorf(sx), cj = (int)floorf(sy);
    if (ci < 0 || cj < 0 || ci >= w || cj >= h) return 0;
    const int start = cj * w + ci;
    if (height[start] < rp->sea_level) return 0;
    const int R = rp->breach_radius > 0 ? rp->breach_radius : 64;
    const int max_len = rp->max_length > 0 ? rp->max_length : 4 * (w + h);

    // 1. Trace: steepest descent, breaching pits.
    std::vector<unsigned char> visited(w * h, 0);
    std::vector<int> path(1, start);
    visited[start] = 1;
    bool junction = false;
    std::vector<int> lake;
    int cur = start;
    while ((int)path.size() < max_len) {
        const int x = cur % w, y = cur / w;
        if (height[cur] < rp->sea_level) break;
        if (x == 0 || y == 0 || x == w - 1 || y == h - 1) break;
        if (cur != start && mask && mask[cur] >= 0.75f) {
            junction = true;
            break;
        }
        int best = -1;
        float best_slope = 0.0f;
        for (int k = 0; k < 8; ++k) {
            const int nb = (y + DY[k]) * w + (x + DX[k]);
            if (visited[nb]) continue;
            const float slope = (height[cur] - height[nb]) / DIST[k];
            if (slope > best_slope) {
                best_slope = slope;
                best = nb;
            }
        }
        if (best >= 0) {
            cur = best;
        } else {
            std::vector<int> spill;
            if (breach(height, w, h, cur, R, rp->sea_level, mask, spill, lake) == BREACH_LAKE) {
                if (mask) {
                    for (size_t k = 0; k < lake.size(); ++k) {
                        if (mask[lake[k]] < 0.5f) mask[lake[k]] = 0.5f;
                    }
                }
                break;
            }
            for (size_t k = 0; k + 1 < spill.size(); ++k) {
                visited[spill[k]] = 1;
                path.push_back(spill[k]);
            }
            cur = spill.back();
        }
        visited[cur] = 1;
        path.push_back(cur);
    }
    if (path.size() < 2) return 0;
    // The junction cell's height is the existing channel's bed.
    const float junction_bed = junction ? height[path.back()] : -1.0f;

    // 2. Smooth the path and compute the bed: height minus a depth growing
    // along the course, made non-increasing downstream.
    std::vector<float> px, py, pz;
    for (size_t k = 0; k < path.size(); ++k) {
        px.push_back((float)(path[k] % w) + 0.5f);
        py.push_back((float)(path[k] / w) + 0.5f);
        pz.push_back(height[path[k]]);
    }
    vnoise::chaikin_xy(px, py, &pz, rp->smooth > 0 ? rp->smooth : 0);
    const size_t n = px.size();
    std::vector<float> bed(n), width(n);
    float run = 1e30f, len = 0.0f;
    for (size_t k = 0; k < n; ++k) {
        if (k > 0) {
            const float dx = px[k] - px[k - 1], dy = py[k] - py[k - 1];
            len += sqrtf(dx * dx + dy * dy);
        }
        float depth = rp->depth0 + rp->depth_growth * len;
        if (depth > rp->max_depth) depth = rp->max_depth;
        float b = pz[k] - depth;
        if (b < 0.0f) b = 0.0f;
        if (b > run) b = run;
        run = b;
        bed[k] = b;
        float wd = rp->width0 + rp->width_growth * len;
        if (wd > rp->max_width) wd = rp->max_width;
        width[k] = wd > 0.5f ? wd : 0.5f;
    }
    if (junction) {
        // A tributary meets the main channel at its bed and never digs below
        // it; max with a constant keeps the bed non-increasing.
        bed[n - 1] = junction_bed;
        for (size_t k = 0; k < n; ++k) {
            if (bed[k] < junction_bed) bed[k] = junction_bed;
        }
    }

    // 3. Carve the channel and valley, and write the mask.
    float wmax = 0.0f;
    for (size_t k = 0; k < n; ++k) wmax = fmaxf(wmax, width[k]);
    const float bank = rp->bank > 0.0f ? rp->bank : 1.0f;
    const float reach = 0.5f * wmax + fmaxf(rp->valley, bank) + 1.0f;
    vnoise::Polyline line;
    line.x = px;
    line.y = py;
    line.build(reach);
    float x0 = 1e30f, y0 = 1e30f, x1 = -1e30f, y1 = -1e30f;
    for (size_t k = 0; k < n; ++k) {
        x0 = fminf(x0, px[k]); y0 = fminf(y0, py[k]);
        x1 = fmaxf(x1, px[k]); y1 = fmaxf(y1, py[k]);
    }
    int i0 = (int)floorf(x0 - reach), i1 = (int)ceilf(x1 + reach);
    int j0 = (int)floorf(y0 - reach), j1 = (int)ceilf(y1 + reach);
    if (i0 < 0) i0 = 0;
    if (j0 < 0) j0 = 0;
    if (i1 > w - 1) i1 = w - 1;
    if (j1 > h - 1) j1 = h - 1;
    const float shape = rp->valley_shape > 0.0f ? rp->valley_shape : 1.0f;
    for (int j = j0; j <= j1; ++j) {
        for (int i = i0; i <= i1; ++i) {
            vnoise::Polyline::Hit hit;
            if (!line.nearest((float)i + 0.5f, (float)j + 0.5f, &hit)) continue;
            const int k = hit.seg;
            const float b = bed[k] + hit.t * (bed[k + 1] - bed[k]);
            const float half = 0.5f * (width[k] + hit.t * (width[k + 1] - width[k]));
            float& cell = height[j * w + i];
            const float s = smoothstepf(half, half + rp->valley, hit.d);
            if (cell > b) {
                const float prof = s >= 1.0f ? 1.0f : (s <= 0.0f ? 0.0f : powf(s, shape));
                cell = clamp01f(b + (cell - b) * prof);
            }
            if (mask) {
                float mv = 0.0f;
                if (hit.d <= half) mv = 1.0f;
                else if (hit.d < half + bank) mv = 1.0f - (hit.d - half) / bank;
                if (mv > mask[j * w + i]) mask[j * w + i] = mv;
            }
        }
    }

    // 4. Points out.
    int count = 0;
    if (out_points) {
        for (size_t k = 0; k < n && count < max_points; ++k, ++count) {
            out_points[2 * count] = px[k];
            out_points[2 * count + 1] = py[k];
        }
    } else {
        count = (int)n < max_points ? (int)n : max_points;
    }
    return count;
}

extern "C" VNOISE_API int vnoise_river_sources(const float* height, int w, int h, int count,
                                               float min_elev, float min_spacing,
                                               unsigned long long seed, float* out_xy) {
    if (!height || !out_xy || w <= 0 || h <= 0 || count <= 0) return 0;
    unsigned long long st = seed ^ 0x5851F42D4C957F2DULL;
    const float span = 1.0f - min_elev > 1e-6f ? 1.0f - min_elev : 1e-6f;
    const float sp2 = min_spacing * min_spacing;
    int found = 0;
    // Rejection sampling weighted by height - min_elev, with a fixed budget.
    const int budget = count * 4000;
    for (int attempt = 0; attempt < budget && found < count; ++attempt) {
        const int i = (int)(next_unit(&st) * (float)w);
        const int j = (int)(next_unit(&st) * (float)h);
        const float accept = next_unit(&st);
        if (i >= w || j >= h) continue;
        const float v = height[j * w + i];
        if (v < min_elev || accept > (v - min_elev) / span) continue;
        const float x = (float)i + 0.5f, y = (float)j + 0.5f;
        bool ok = true;
        for (int k = 0; k < found && ok; ++k) {
            const float dx = out_xy[2 * k] - x, dy = out_xy[2 * k + 1] - y;
            ok = dx * dx + dy * dy >= sp2;
        }
        if (!ok) continue;
        out_xy[2 * found] = x;
        out_xy[2 * found + 1] = y;
        ++found;
    }
    return found;
}
