#ifndef VNOISE_HYDROLOGY_H
#define VNOISE_HYDROLOGY_H

#include <vector>
#include "vnoise/internal.h"

// Hydrology shared by the terrain plan (terrain_plan.cpp) and the matrix
// operations (matrix_filters.cpp, matrix_rivers.cpp): depression filling,
// steepest-descent routing, flow accumulation, implicit stream-power erosion
// and Chaikin smoothing, on a row-major grid of `mw * mh` nodes. Heights are
// doubles so the flood increments (1e-6) stay exact at any height. Every
// function is deterministic (fixed neighbor order breaks ties).

namespace vnoise {
namespace hydro {

extern const double FLOOD_EPSILON;
extern const double SQRT2;
// Fixed neighbor order: 4 orthogonal neighbors first, then the diagonals.
extern const int NDX[8];
extern const int NDY[8];
extern const double NDIST[8];

struct Grid {
    int mw, mh, n;

    bool neighbor(int idx, int k, int* out) const {
        const int i = idx % mw + NDX[k];
        const int j = idx / mw + NDY[k];
        if (i < 0 || j < 0 || i >= mw || j >= mh) return false;
        *out = j * mw + i;
        return true;
    }

    bool boundary(int idx) const {
        const int i = idx % mw, j = idx / mw;
        return i == 0 || j == 0 || i == mw - 1 || j == mh - 1;
    }
};

// Drainage of the current heights: depression filling, receivers, stack
// order and A^m (the stream-power factor), reused for several erosion steps.
struct Drainage {
    std::vector<double> F, A, Am;
    std::vector<int> recv, order;
};

// Stream-power parameters of one erosion step.
struct ErosionParams {
    float k, dt, diffusion;
};

// Outlets: boundary nodes (VNOISE_OUTLETS_EDGES), nodes below sea level
// (VNOISE_OUTLETS_SEA) or both; with no outlet, the lowest boundary node.
void mark_outlets(const Grid& g, const std::vector<double>& H, float sea_level, int outlets,
                  std::vector<unsigned char>& outlet);
// Priority-flood with an epsilon increment: F >= H, and every non-outlet node
// gets a strictly lower 8-neighbor in F.
void priority_flood(const Grid& g, const std::vector<double>& H,
                    const std::vector<unsigned char>& outlet, std::vector<double>& F);
// Steepest-descent receivers on F (-1 for outlets).
void route(const Grid& g, const std::vector<double>& F, const std::vector<unsigned char>& outlet,
           std::vector<int>& recv);
// Topological order from the outlets upstream.
void stack_order(const Grid& g, const std::vector<int>& recv, std::vector<int>& order);
// Flow accumulation in nodes.
void accumulate(const Grid& g, const std::vector<int>& recv, const std::vector<int>& order,
                std::vector<double>& A);
// 1 or sqrt(2) between two neighbor nodes.
double receiver_distance(const Grid& g, int a, int b);
// Recomputes a drainage for heights H.
void drain(const Grid& g, float m, const std::vector<double>& H,
           const std::vector<unsigned char>& outlet, Drainage& dr);
// One implicit stream-power step over a drainage, then hillslope diffusion.
void erosion_step(const Grid& g, const ErosionParams& p, const std::vector<double>& U,
                  const Drainage& dr, std::vector<double>& H, std::vector<double>& scratch,
                  const std::vector<unsigned char>& outlet);
// Chaikin corner cutting on parallel attribute arrays, keeping both ends.
void chaikin(std::vector<std::vector<double> >& attrs, int passes);

} // namespace hydro
} // namespace vnoise

#endif
