#include <cmath>
#include <queue>
#include <utility>
#include <vector>
#include "hydrology.h"

// Implementation of the shared hydrology (see hydrology.h). Moved verbatim
// from terrain_plan.cpp so plans keep their exact results.

namespace vnoise {
namespace hydro {

extern const double FLOOD_EPSILON = 1e-6;
extern const double SQRT2 = 1.4142135623730951;

// Fixed neighbor order: it breaks every tie, so plans are deterministic.
extern const int NDX[8] = { 1, -1, 0, 0, 1, -1, 1, -1 };
extern const int NDY[8] = { 0, 0, 1, -1, 1, 1, -1, -1 };
extern const double NDIST[8] = { 1, 1, 1, 1, SQRT2, SQRT2, SQRT2, SQRT2 };



// Outlets: boundary nodes, nodes below sea level, or both. With "sea" and no
// node under the sea, the lowest boundary node (first in index order on ties)
// drains the map.
void mark_outlets(const Grid& g, const std::vector<double>& H, float sea_level, int outlets,
                  std::vector<unsigned char>& outlet) {
    outlet.assign(g.n, 0);
    int count = 0;
    for (int idx = 0; idx < g.n; ++idx) {
        const bool edge = g.boundary(idx);
        const bool sea = H[idx] < (double)sea_level;
        bool o = false;
        if (outlets == VNOISE_OUTLETS_EDGES) o = edge;
        else if (outlets == VNOISE_OUTLETS_SEA) o = sea;
        else o = edge || sea;
        outlet[idx] = o ? 1 : 0;
        count += o ? 1 : 0;
    }
    if (count == 0) {
        int best = -1;
        for (int idx = 0; idx < g.n; ++idx) {
            if (g.boundary(idx) && (best < 0 || H[idx] < H[best])) best = idx;
        }
        if (best >= 0) outlet[best] = 1;
    }
}

// Priority-flood with an epsilon increment (Barnes, Lehman & Mulla 2014):
// F >= H and every non-outlet node gets a strictly lower neighbor in F.
void priority_flood(const Grid& g, const std::vector<double>& H,
                    const std::vector<unsigned char>& outlet, std::vector<double>& F) {
    typedef std::pair<double, int> Item;
    std::priority_queue<Item, std::vector<Item>, std::greater<Item> > open;
    std::vector<int> pit;
    size_t pit_head = 0;
    std::vector<unsigned char> closed(g.n, 0);
    F.assign(g.n, 0.0);
    for (int idx = 0; idx < g.n; ++idx) {
        if (outlet[idx]) {
            F[idx] = H[idx];
            closed[idx] = 1;
            open.push(Item(F[idx], idx));
        }
    }
    while (!open.empty() || pit_head < pit.size()) {
        int c;
        if (pit_head < pit.size()) {
            c = pit[pit_head++];
            if (pit_head == pit.size()) {
                pit.clear();
                pit_head = 0;
            }
        } else {
            c = open.top().second;
            open.pop();
        }
        for (int k = 0; k < 8; ++k) {
            int nb;
            if (!g.neighbor(c, k, &nb) || closed[nb]) continue;
            closed[nb] = 1;
            if (H[nb] <= F[c] + FLOOD_EPSILON) {
                F[nb] = F[c] + FLOOD_EPSILON;
                pit.push_back(nb);
            } else {
                F[nb] = H[nb];
                open.push(Item(F[nb], nb));
            }
        }
    }
}

// Steepest-descent (D8) receivers on F; ties keep the first neighbor.
void route(const Grid& g, const std::vector<double>& F, const std::vector<unsigned char>& outlet,
           std::vector<int>& recv) {
    recv.assign(g.n, -1);
    for (int idx = 0; idx < g.n; ++idx) {
        if (outlet[idx]) continue;
        int best = -1;
        double best_slope = 0.0;
        for (int k = 0; k < 8; ++k) {
            int nb;
            if (!g.neighbor(idx, k, &nb)) continue;
            const double slope = (F[idx] - F[nb]) / NDIST[k];
            if (slope > best_slope) {
                best_slope = slope;
                best = nb;
            }
        }
        recv[idx] = best;
    }
}

// Topological order from the outlets upstream (every node after its
// receiver), built with an explicit stack over the donor lists.
void stack_order(const Grid& g, const std::vector<int>& recv, std::vector<int>& order) {
    std::vector<int> dstart(g.n + 1, 0), donors(g.n);
    for (int idx = 0; idx < g.n; ++idx) {
        if (recv[idx] >= 0) dstart[recv[idx] + 1]++;
    }
    for (int idx = 0; idx < g.n; ++idx) dstart[idx + 1] += dstart[idx];
    std::vector<int> fill(dstart.begin(), dstart.end() - 1);
    for (int idx = 0; idx < g.n; ++idx) {
        if (recv[idx] >= 0) donors[fill[recv[idx]]++] = idx;
    }
    order.clear();
    order.reserve(g.n);
    std::vector<int> st;
    for (int root = 0; root < g.n; ++root) {
        if (recv[root] >= 0) continue;
        st.push_back(root);
        while (!st.empty()) {
            const int c = st.back();
            st.pop_back();
            order.push_back(c);
            for (int k = dstart[c]; k < dstart[c + 1]; ++k) st.push_back(donors[k]);
        }
    }
}

void accumulate(const Grid& g, const std::vector<int>& recv, const std::vector<int>& order,
                std::vector<double>& A) {
    A.assign(g.n, 1.0);
    for (int k = (int)order.size() - 1; k >= 0; --k) {
        const int c = order[k];
        if (recv[c] >= 0) A[recv[c]] += A[c];
    }
}

double receiver_distance(const Grid& g, int a, int b) {
    return (a % g.mw != b % g.mw && a / g.mw != b / g.mw) ? SQRT2 : 1.0;
}

// Drainage of the current heights: depression filling, receivers, stack
// order and A^m (the stream-power factor), reused for `reroute` steps.


void drain(const Grid& g, float m, const std::vector<double>& H,
           const std::vector<unsigned char>& outlet, Drainage& dr) {
    priority_flood(g, H, outlet, dr.F);
    route(g, dr.F, outlet, dr.recv);
    stack_order(g, dr.recv, dr.order);
    accumulate(g, dr.recv, dr.order, dr.A);
    dr.Am.resize(g.n);
    for (int idx = 0; idx < g.n; ++idx) dr.Am[idx] = pow(dr.A[idx], (double)m);
}

// One implicit stream-power step (Braun & Willett 2013, n = 1) over the
// given drainage, followed by explicit linear hillslope diffusion. Nodes not
// above their receiver (in a depression) only get uplift.
void erosion_step(const Grid& g, const ErosionParams& p, const std::vector<double>& U,
                  const Drainage& dr, std::vector<double>& H, std::vector<double>& scratch,
                  const std::vector<unsigned char>& outlet) {
    const double dt = p.dt, K = p.k;
    for (size_t k = 0; k < dr.order.size(); ++k) {
        const int c = dr.order[k];
        const int r = dr.recv[c];
        if (r < 0 || outlet[c]) continue;
        const double up = dt * U[c];
        if (H[c] <= H[r]) {
            H[c] += up;
            continue;
        }
        const double f = dt * K * dr.Am[c] / receiver_distance(g, c, r);
        H[c] = (H[c] + up + f * H[r]) / (1.0 + f);
    }
    const double D = p.diffusion;
    if (D > 0.0) {
        scratch = H;
        for (int idx = 0; idx < g.n; ++idx) {
            if (outlet[idx]) continue;
            double lap = 0.0;
            for (int k = 0; k < 4; ++k) {
                int nb;
                if (g.neighbor(idx, k, &nb)) lap += scratch[nb] - scratch[idx];
            }
            H[idx] = scratch[idx] + D * lap;
        }
    }
}

void chaikin(std::vector<std::vector<double> >& attrs, int passes) {
    for (int pass = 0; pass < passes; ++pass) {
        const size_t n = attrs[0].size();
        if (n < 3) return;
        for (size_t a = 0; a < attrs.size(); ++a) {
            const std::vector<double>& v = attrs[a];
            std::vector<double> out;
            out.reserve(2 * n);
            out.push_back(v[0]);
            for (size_t k = 0; k + 1 < n; ++k) {
                out.push_back(0.75 * v[k] + 0.25 * v[k + 1]);
                out.push_back(0.25 * v[k] + 0.75 * v[k + 1]);
            }
            out.push_back(v[n - 1]);
            attrs[a].swap(out);
        }
    }
}


} // namespace hydro
} // namespace vnoise
