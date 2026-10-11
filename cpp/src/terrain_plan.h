#ifndef VNOISE_TERRAIN_PLAN_H
#define VNOISE_TERRAIN_PLAN_H

#include <vector>
#include "vnoise/internal.h"

// Private layout of vnoise_plan_t, shared by terrain_plan.cpp (build) and
// terrain_fill.cpp (per-block evaluation). The plan is immutable after
// vnoise_plan_create returns.
struct vnoise_plan {
    vnoise_plan_params_t p;
    int mw = 0, mh = 0, n = 0;  // macro grid size and node count
    noise_state_t state;        // the plan's own state (meander warp)

    // Macro grids, mw * mh each, row-major (node (i, j) at j * mw + i).
    std::vector<float> height;  // eroded height H, 0..1
    std::vector<float> filled;  // depression-filled height F >= H
    std::vector<float> flow;    // flow accumulation A, in nodes
    std::vector<float> lake;    // 1 for lake nodes
    std::vector<int> receiver;  // steepest-descent receiver, -1 for outlets
    std::vector<unsigned char> outlet;
    float flow_max = 1.0f;

    // River network: polylines of consecutive vertices.
    std::vector<int> poly_start, poly_count, poly_mouth;
    std::vector<float> vx, vy, vflow, vwidth, vbed;
    std::vector<int> vpoly;     // polyline index of each vertex

    // Uniform bucket index of the segments (k, k + 1) by first vertex k.
    int pad = 0;                // buckets added on each side of the extent
    int nbx = 0, nby = 0;
    std::vector<int> bucket_start;  // nbx * nby + 1 offsets into bucket_items
    std::vector<int> bucket_items;
};

namespace vnoise {

// Result of a river query at a cell.
struct RiverHit {
    float d, bed, width, flow;
    int poly;
};

// Nearest indexed river segment to cell (c, r), after the meander warp.
bool plan_query(const vnoise_plan* plan, float c, float r, RiverHit* hit);

// Valley half-width for a channel of width w (cells).
inline float valley_half_width(const vnoise_plan_params_t& p, float w) {
    return p.valley * w * 0.5f + p.valley_min;
}

} // namespace vnoise

#endif
