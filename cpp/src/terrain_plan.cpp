#include <cmath>
#include <queue>
#include <utility>
#include <vector>
#include "terrain_plan.h"

// Terrain plan build: macro grid, stream-power erosion, priority-flood,
// D8 routing, flow accumulation, lakes, river extraction and its spatial
// index. Everything here is O(nodes) or O(nodes log nodes) per pass and never
// depends on the cell extent. Heights are processed in double precision so the
// flood increments (1e-6) stay exact at any height.

namespace {

const double FLOOD_EPSILON = 1e-6;
const int MAX_NODES = 1048576;
const double SQRT2 = 1.4142135623730951;

// Fixed neighbor order: it breaks every tie, so plans are deterministic.
const int NDX[8] = { 1, -1, 0, 0, 1, -1, 1, -1 };
const int NDY[8] = { 0, 0, 1, -1, 1, 1, -1, -1 };
const double NDIST[8] = { 1, 1, 1, 1, SQRT2, SQRT2, SQRT2, SQRT2 };

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

// Outlets: boundary nodes, nodes below sea level, or both. With "sea" and no
// node under the sea, the lowest boundary node (first in index order on ties)
// drains the map.
void mark_outlets(const Grid& g, const std::vector<double>& H, const vnoise_plan_params_t& p,
                  std::vector<unsigned char>& outlet) {
    outlet.assign(g.n, 0);
    int count = 0;
    for (int idx = 0; idx < g.n; ++idx) {
        const bool edge = g.boundary(idx);
        const bool sea = H[idx] < (double)p.sea_level;
        bool o = false;
        if (p.outlets == VNOISE_OUTLETS_EDGES) o = edge;
        else if (p.outlets == VNOISE_OUTLETS_SEA) o = sea;
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
struct Drainage {
    std::vector<double> F, A, Am;
    std::vector<int> recv, order;
};

void drain(const Grid& g, const vnoise_plan_params_t& p, const std::vector<double>& H,
           const std::vector<unsigned char>& outlet, Drainage& dr) {
    priority_flood(g, H, outlet, dr.F);
    route(g, dr.F, outlet, dr.recv);
    stack_order(g, dr.recv, dr.order);
    accumulate(g, dr.recv, dr.order, dr.A);
    dr.Am.resize(g.n);
    for (int idx = 0; idx < g.n; ++idx) dr.Am[idx] = pow(dr.A[idx], (double)p.erosion_m);
}

// One implicit stream-power step (Braun & Willett 2013, n = 1) over the
// given drainage, followed by explicit linear hillslope diffusion. Nodes not
// above their receiver (in a depression) only get uplift.
void erosion_step(const Grid& g, const vnoise_plan_params_t& p, const std::vector<double>& U,
                  const Drainage& dr, std::vector<double>& H, std::vector<double>& scratch,
                  const std::vector<unsigned char>& outlet) {
    const double dt = p.erosion_dt, K = p.erosion_k;
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
    const double D = p.erosion_diffusion;
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

float clamp01(float v) {
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

// Chaikin corner cutting on parallel attribute arrays, keeping both ends.
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

// Extracts the river network into polylines (see the terrain-plan spec).
void extract_rivers(vnoise_plan* plan, const Grid& g, const std::vector<double>& F,
                    const std::vector<double>& A, const std::vector<unsigned char>& sea) {
    const vnoise_plan_params_t& p = plan->p;
    const double min_flow = p.river_min_flow > 1.0f ? p.river_min_flow : 1.0;
    std::vector<unsigned char> river(g.n, 0);
    std::vector<int> river_donors(g.n, 0);
    for (int idx = 0; idx < g.n; ++idx) {
        river[idx] = (!sea[idx] && A[idx] >= min_flow) ? 1 : 0;
    }
    for (int idx = 0; idx < g.n; ++idx) {
        const int r = plan->receiver[idx];
        if (river[idx] && r >= 0) river_donors[r]++;
    }
    const double mc = p.macro_cell;
    for (int s = 0; s < g.n; ++s) {
        if (!river[s] || river_donors[s] == 1) continue;  // starts: sources and confluences
        std::vector<int> nodes(1, s);
        int mouth = VNOISE_MOUTH_EDGE;
        int cur = s;
        for (;;) {
            const int r = plan->receiver[cur];
            if (r < 0) {
                mouth = VNOISE_MOUTH_EDGE;
                break;
            }
            nodes.push_back(r);
            if (sea[r]) {
                mouth = VNOISE_MOUTH_SEA;
                break;
            }
            if (river_donors[r] >= 2) {
                mouth = VNOISE_MOUTH_RIVER;
                break;
            }
            cur = r;
        }
        if (nodes.size() < 2) continue;
        std::vector<std::vector<double> > attrs(4);
        for (size_t k = 0; k < nodes.size(); ++k) {
            const int nd = nodes[k];
            attrs[0].push_back((nd % g.mw) * mc);
            attrs[1].push_back((nd / g.mw) * mc);
            attrs[2].push_back(A[nd]);
            attrs[3].push_back(F[nd]);
        }
        chaikin(attrs, p.river_smooth);
        const int poly = (int)plan->poly_start.size();
        plan->poly_start.push_back((int)plan->vx.size());
        plan->poly_count.push_back((int)attrs[0].size());
        plan->poly_mouth.push_back(mouth);
        double running = 1e30;
        for (size_t k = 0; k < attrs[0].size(); ++k) {
            const double ratio = sqrt(attrs[2][k] / min_flow);
            double width = p.river_width * ratio;
            if (width > p.river_max_width) width = p.river_max_width;
            double depth = p.river_depth * ratio;
            if (depth > p.river_max_depth) depth = p.river_max_depth;
            double bed = attrs[3][k] - depth;
            if (bed < 0.0) bed = 0.0;
            if (bed > 1.0) bed = 1.0;
            if (bed > running) bed = running;  // never rises downstream
            running = bed;
            plan->vx.push_back((float)attrs[0][k]);
            plan->vy.push_back((float)attrs[1][k]);
            plan->vflow.push_back((float)attrs[2][k]);
            plan->vwidth.push_back((float)width);
            plan->vbed.push_back((float)bed);
            plan->vpoly.push_back(poly);
        }
    }
}

// Registers every segment in the buckets overlapped by its capsule's bounding
// box (a superset of the capsule).
void build_index(vnoise_plan* plan) {
    const vnoise_plan_params_t& p = plan->p;
    const float mc = (float)p.macro_cell;
    float rmax = 0.0f;
    const int nv = (int)plan->vx.size();
    std::vector<float> radius(nv, 0.0f);
    for (int k = 0; k + 1 < nv; ++k) {
        if (plan->vpoly[k] != plan->vpoly[k + 1]) continue;
        const float w = plan->vwidth[k] > plan->vwidth[k + 1] ? plan->vwidth[k] : plan->vwidth[k + 1];
        radius[k] = w * 0.5f + vnoise::valley_half_width(p, w) + p.meander_amp;
        if (radius[k] > rmax) rmax = radius[k];
    }
    plan->pad = (int)ceilf(rmax / mc) + 1;
    plan->nbx = (plan->mw - 1) + 2 * plan->pad + 1;
    plan->nby = (plan->mh - 1) + 2 * plan->pad + 1;
    const int nb = plan->nbx * plan->nby;
    const float origin = -(float)plan->pad * mc;
    std::vector<int> counts(nb + 1, 0);
    // Two passes: count, then fill (compressed rows).
    for (int pass = 0; pass < 2; ++pass) {
        std::vector<int> fill;
        if (pass == 1) {
            plan->bucket_start.assign(nb + 1, 0);
            for (int b = 0; b < nb; ++b) plan->bucket_start[b + 1] = plan->bucket_start[b] + counts[b];
            plan->bucket_items.assign(plan->bucket_start[nb], 0);
            fill.assign(plan->bucket_start.begin(), plan->bucket_start.end() - 1);
        }
        for (int k = 0; k + 1 < nv; ++k) {
            if (plan->vpoly[k] != plan->vpoly[k + 1]) continue;
            const float r = radius[k];
            const float x0 = fminf(plan->vx[k], plan->vx[k + 1]) - r;
            const float x1 = fmaxf(plan->vx[k], plan->vx[k + 1]) + r;
            const float y0 = fminf(plan->vy[k], plan->vy[k + 1]) - r;
            const float y1 = fmaxf(plan->vy[k], plan->vy[k + 1]) + r;
            int bx0 = (int)floorf((x0 - origin) / mc), bx1 = (int)floorf((x1 - origin) / mc);
            int by0 = (int)floorf((y0 - origin) / mc), by1 = (int)floorf((y1 - origin) / mc);
            if (bx0 < 0) bx0 = 0;
            if (by0 < 0) by0 = 0;
            if (bx1 >= plan->nbx) bx1 = plan->nbx - 1;
            if (by1 >= plan->nby) by1 = plan->nby - 1;
            for (int by = by0; by <= by1; ++by) {
                for (int bx = bx0; bx <= bx1; ++bx) {
                    const int b = by * plan->nbx + bx;
                    if (pass == 0) counts[b]++;
                    else plan->bucket_items[fill[b]++] = k;
                }
            }
        }
    }
}

bool valid_params(const vnoise_plan_params_t* p) {
    if (p->width < 1 || p->width > 65536 || p->height < 1 || p->height > 65536) return false;
    if (p->macro_cell < 4) return false;
    if (!(p->sea_level >= 0.0f && p->sea_level <= 1.0f)) return false;
    if (p->outlets < VNOISE_OUTLETS_EDGES || p->outlets > VNOISE_OUTLETS_BOTH) return false;
    if (p->erosion_iterations < 0 || p->erosion_reroute < 1 || p->river_smooth < 0) return false;
    if (!(p->erosion_diffusion >= 0.0f && p->erosion_diffusion <= 0.25f)) return false;
    if (!(p->erosion_k >= 0.0f && p->erosion_dt >= 0.0f && p->erosion_m >= 0.0f)) return false;
    if (!(p->river_width > 0.0f && p->river_max_width >= p->river_width)) return false;
    if (!(p->river_depth >= 0.0f && p->river_max_depth >= 0.0f)) return false;
    if (!(p->valley >= 0.0f && p->valley_min >= 0.0f && p->valley_shape > 0.0f)) return false;
    if (!(p->bank > 0.0f && p->meander_amp >= 0.0f && p->distance_range > 0.0f)) return false;
    if (!(p->detail_amplitude >= 0.0f && p->detail_valley_damping >= 0.0f &&
          p->detail_valley_damping <= 1.0f)) return false;
    return true;
}

} // namespace

namespace vnoise {

bool plan_query(const vnoise_plan* plan, float c, float r, RiverHit* hit) {
    if (plan->bucket_items.empty()) return false;
    const vnoise_plan_params_t& p = plan->p;
    float x = c, y = r;
    if (p.meander_amp > 0.0f) {
        const float fx = c * p.meander_freq, fy = r * p.meander_freq;
        float nx = 1.5f * fbm_sample(&plan->state, VNOISE_BASE_SIMPLEX2, fx + 5.2f, fy + 1.3f, 3, 2.0f, 0.5f, FBM);
        float ny = 1.5f * fbm_sample(&plan->state, VNOISE_BASE_SIMPLEX2, fx + 1.7f, fy + 9.2f, 3, 2.0f, 0.5f, FBM);
        nx = nx < -1.0f ? -1.0f : (nx > 1.0f ? 1.0f : nx);
        ny = ny < -1.0f ? -1.0f : (ny > 1.0f ? 1.0f : ny);
        x += p.meander_amp * nx;
        y += p.meander_amp * ny;
    }
    const float mc = (float)p.macro_cell;
    const float origin = -(float)plan->pad * mc;
    const int bx = (int)floorf((x - origin) / mc);
    const int by = (int)floorf((y - origin) / mc);
    if (bx < 0 || by < 0 || bx >= plan->nbx || by >= plan->nby) return false;
    const int b = by * plan->nbx + bx;
    const int first = plan->bucket_start[b], last = plan->bucket_start[b + 1];
    if (first == last) return false;
    float best = 1e30f, best_t = 0.0f;
    int best_k = -1;
    for (int it = first; it < last; ++it) {
        const int k = plan->bucket_items[it];
        const float ax = plan->vx[k], ay = plan->vy[k];
        const float ex = plan->vx[k + 1] - ax, ey = plan->vy[k + 1] - ay;
        const float len2 = ex * ex + ey * ey;
        float t = len2 > 0.0f ? ((x - ax) * ex + (y - ay) * ey) / len2 : 0.0f;
        t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
        const float dx = ax + t * ex - x, dy = ay + t * ey - y;
        const float d2 = dx * dx + dy * dy;
        if (d2 < best) {
            best = d2;
            best_t = t;
            best_k = k;
        }
    }
    const int k = best_k;
    const float t = best_t;
    hit->d = sqrtf(best);
    hit->bed = plan->vbed[k] + t * (plan->vbed[k + 1] - plan->vbed[k]);
    hit->width = plan->vwidth[k] + t * (plan->vwidth[k + 1] - plan->vwidth[k]);
    hit->flow = plan->vflow[k] + t * (plan->vflow[k + 1] - plan->vflow[k]);
    hit->poly = plan->vpoly[k];
    return true;
}

} // namespace vnoise

extern "C" {

VNOISE_API vnoise_plan_t* vnoise_plan_create(const vnoise_plan_params_t* params,
                                             const float* height, const float* uplift) {
    if (!params || !height || !valid_params(params)) return 0;
    const int mc = params->macro_cell;
    const long long mw = (params->width + mc - 1) / mc + 1;
    const long long mh = (params->height + mc - 1) / mc + 1;
    if (mw * mh > MAX_NODES) return 0;

    vnoise_plan* plan = new vnoise_plan();
    plan->p = *params;
    plan->mw = (int)mw;
    plan->mh = (int)mh;
    plan->n = (int)(mw * mh);
    noise_init(&plan->state, params->seed);
    const Grid g = { plan->mw, plan->mh, plan->n };

    std::vector<double> H(g.n), U(g.n, 0.0);
    for (int idx = 0; idx < g.n; ++idx) {
        H[idx] = clamp01(height[idx]);
        if (uplift) U[idx] = (double)clamp01(uplift[idx]) * params->erosion_uplift;
    }
    // Outlets come from the input height and stay fixed during erosion.
    mark_outlets(g, H, *params, plan->outlet);

    std::vector<double> scratch;
    Drainage dr;
    for (int it = 0; it < params->erosion_iterations; ++it) {
        if (it % params->erosion_reroute == 0) drain(g, *params, H, plan->outlet, dr);
        erosion_step(g, *params, U, dr, H, scratch, plan->outlet);
    }
    if (params->erosion_iterations > 0) {
        // Keep 0..1: rescale the land part if uplift pushed it above 1.
        const double sea = params->sea_level;
        double land_max = -1.0;
        for (int idx = 0; idx < g.n; ++idx) {
            if (H[idx] >= sea && H[idx] > land_max) land_max = H[idx];
        }
        const bool rescale = land_max > 1.0;
        for (int idx = 0; idx < g.n; ++idx) {
            if (rescale && H[idx] >= sea) H[idx] = sea + (H[idx] - sea) * (1.0 - sea) / (land_max - sea);
            if (H[idx] < 0.0) H[idx] = 0.0;
            if (H[idx] > 1.0) H[idx] = 1.0;
        }
    }

    // Erosion can lower land under the sea: outlets of the final drainage come
    // from the final height.
    if (params->erosion_iterations > 0) mark_outlets(g, H, *params, plan->outlet);
    std::vector<double> F, A;
    std::vector<int> order;
    priority_flood(g, H, plan->outlet, F);
    route(g, F, plan->outlet, plan->receiver);
    stack_order(g, plan->receiver, order);
    accumulate(g, plan->receiver, order, A);

    plan->height.resize(g.n);
    plan->filled.resize(g.n);
    plan->flow.resize(g.n);
    plan->lake.resize(g.n);
    std::vector<unsigned char> sea(g.n, 0);
    plan->flow_max = 1.0f;
    for (int idx = 0; idx < g.n; ++idx) {
        plan->height[idx] = (float)H[idx];
        plan->filled[idx] = (float)F[idx];
        plan->flow[idx] = (float)A[idx];
        if (plan->flow[idx] > plan->flow_max) plan->flow_max = plan->flow[idx];
        plan->lake[idx] = (F[idx] - H[idx] > (double)params->lake_depth) ? 1.0f : 0.0f;
        sea[idx] = (plan->outlet[idx] && H[idx] < (double)params->sea_level) ? 1 : 0;
    }
    extract_rivers(plan, g, F, A, sea);
    build_index(plan);
    return plan;
}

VNOISE_API void vnoise_plan_destroy(vnoise_plan_t* plan) {
    delete plan;
}

VNOISE_API void vnoise_plan_info(const vnoise_plan_t* plan, int* mw, int* mh,
                                 int* polylines, int* vertices) {
    if (!plan) return;
    if (mw) *mw = plan->mw;
    if (mh) *mh = plan->mh;
    if (polylines) *polylines = (int)plan->poly_start.size();
    if (vertices) *vertices = (int)plan->vx.size();
}

VNOISE_API void vnoise_plan_grid(const vnoise_plan_t* plan, int which, float* out) {
    if (!plan || !out) return;
    for (int idx = 0; idx < plan->n; ++idx) {
        float v = 0.0f;
        switch (which) {
        case VNOISE_GRID_HEIGHT: v = plan->height[idx]; break;
        case VNOISE_GRID_FILLED: v = plan->filled[idx]; break;
        case VNOISE_GRID_FLOW: v = plan->flow[idx]; break;
        case VNOISE_GRID_LAKE: v = plan->lake[idx]; break;
        case VNOISE_GRID_RECEIVER: v = (float)plan->receiver[idx]; break;
        case VNOISE_GRID_OUTLET: v = plan->outlet[idx] ? 1.0f : 0.0f; break;
        default: return;
        }
        out[idx] = v;
    }
}

VNOISE_API void vnoise_plan_rivers(const vnoise_plan_t* plan, int* start, int* count, int* mouth,
                                   float* x, float* y, float* flow, float* width, float* bed) {
    if (!plan) return;
    for (size_t k = 0; k < plan->poly_start.size(); ++k) {
        if (start) start[k] = plan->poly_start[k];
        if (count) count[k] = plan->poly_count[k];
        if (mouth) mouth[k] = plan->poly_mouth[k];
    }
    for (size_t k = 0; k < plan->vx.size(); ++k) {
        if (x) x[k] = plan->vx[k];
        if (y) y[k] = plan->vy[k];
        if (flow) flow[k] = plan->vflow[k];
        if (width) width[k] = plan->vwidth[k];
        if (bed) bed[k] = plan->vbed[k];
    }
}

VNOISE_API int vnoise_plan_query(const vnoise_plan_t* plan, float c, float r, float* out) {
    if (!plan || !out) return 0;
    vnoise::RiverHit hit;
    if (!vnoise::plan_query(plan, c, r, &hit)) return 0;
    out[0] = hit.d;
    out[1] = hit.bed;
    out[2] = hit.width;
    out[3] = hit.flow;
    out[4] = (float)hit.poly;
    return 1;
}

}
