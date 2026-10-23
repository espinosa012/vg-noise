#include <algorithm>
#include <cmath>
#include <vector>
#include "vnoise/internal.h"
#include "hydrology.h"

// Drainage of a whole matrix: flow accumulation (D8 or multiple flow
// directions) over the depression-filled heights, the topographic wetness
// index of that accumulation, and a river network that
// follows the D8 drainage from every channel head to the sea, the edge or a
// larger river, carving all channels in one pass over a segment index.

namespace {

using namespace vnoise::hydro;

inline float clamp01(float v) {
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

inline float smoothstep(float e0, float e1, float v) {
    if (e1 <= e0) return v < e0 ? 0.0f : 1.0f;
    const float t = clamp01((v - e0) / (e1 - e0));
    return t * t * (3.0f - 2.0f * t);
}

// Heights, outlets and the depression-filled surface of a matrix.
struct Surface {
    Grid g;
    std::vector<double> H, F;
    std::vector<unsigned char> outlet;
};

void build_surface(const float* m, int w, int h, float sea_level, int outlets, Surface& s) {
    s.g.mw = w;
    s.g.mh = h;
    s.g.n = w * h;
    s.H.resize(s.g.n);
    for (int k = 0; k < s.g.n; ++k) s.H[k] = clamp01(m[k]);
    mark_outlets(s.g, s.H, sea_level, outlets, s.outlet);
    priority_flood(s.g, s.H, s.outlet, s.F);
}

// D8 accumulation of the rain (1 per cell without a rain matrix).
void accumulate_d8(const Surface& s, const float* rain, std::vector<int>& recv,
                   std::vector<int>& order, std::vector<double>& A) {
    route(s.g, s.F, s.outlet, recv);
    stack_order(s.g, recv, order);
    A.resize(s.g.n);
    for (int k = 0; k < s.g.n; ++k) A[k] = rain ? (double)clamp01(rain[k]) : 1.0;
    for (int k = (int)order.size() - 1; k >= 0; --k) {
        const int c = order[k];
        if (recv[c] >= 0) A[recv[c]] += A[c];
    }
}

// Multiple flow directions (Freeman 1991): every cell, highest first, shares
// its water among its lower neighbors in proportion to slope^exponent.
void accumulate_mfd(const Surface& s, const float* rain, float exponent, std::vector<double>& A) {
    const Grid& g = s.g;
    A.resize(g.n);
    for (int k = 0; k < g.n; ++k) A[k] = rain ? (double)clamp01(rain[k]) : 1.0;
    std::vector<int> idx(g.n);
    for (int k = 0; k < g.n; ++k) idx[k] = k;
    const std::vector<double>& F = s.F;
    std::sort(idx.begin(), idx.end(), [&F](int a, int b) { return F[a] > F[b] || (F[a] == F[b] && a < b); });
    const double p = exponent > 0.0f ? exponent : 1.1;
    for (int t = 0; t < g.n; ++t) {
        const int c = idx[t];
        if (s.outlet[c]) continue;
        double wts[8], total = 0.0;
        for (int k = 0; k < 8; ++k) {
            wts[k] = 0.0;
            int nb;
            if (!g.neighbor(c, k, &nb)) continue;
            const double slope = (F[c] - F[nb]) / NDIST[k];
            if (slope <= 0.0) continue;
            wts[k] = pow(slope, p);
            total += wts[k];
        }
        if (total <= 0.0) continue;
        for (int k = 0; k < 8; ++k) {
            int nb;
            if (wts[k] > 0.0 && g.neighbor(c, k, &nb)) A[nb] += A[c] * wts[k] / total;
        }
    }
}

void write_flow(const std::vector<double>& A, int n, int scale, float range, float* out) {
    double amax = 1e-12;
    for (int k = 0; k < n; ++k) amax = A[k] > amax ? A[k] : amax;
    const double lmax = log(1.0 + amax);
    for (int k = 0; k < n; ++k) {
        double v;
        if (scale == VNOISE_FLOW_LINEAR) v = A[k] / amax;
        else if (scale == VNOISE_FLOW_RANGE) v = A[k] / (range > 0.0f ? range : 1.0);
        else v = lmax > 0.0 ? log(1.0 + A[k]) / lmax : 0.0;
        out[k] = clamp01((float)v);
    }
}

// One channel segment with its bed and half-width at both ends.
struct Segment {
    float x0, y0, x1, y1;
    float b0, b1, h0, h1;
};

// Uniform bucket index over the segments of every river: each segment is
// registered in every bucket its bounding box grown by `reach` overlaps.
struct SegmentIndex {
    float size = 8.0f;
    int bw = 0, bh = 0;
    std::vector<int> start, items;

    void build(const std::vector<Segment>& segs, int w, int h, float reach) {
        size = fmaxf(8.0f, reach);
        bw = (int)ceilf((float)w / size) + 1;
        bh = (int)ceilf((float)h / size) + 1;
        std::vector<int> counts(bw * bh, 0);
        for (int pass = 0; pass < 2; ++pass) {
            std::vector<int> fill;
            if (pass == 1) {
                start.assign(bw * bh + 1, 0);
                for (int b = 0; b < bw * bh; ++b) start[b + 1] = start[b] + counts[b];
                items.assign(start[bw * bh], 0);
                fill.assign(start.begin(), start.end() - 1);
            }
            for (size_t k = 0; k < segs.size(); ++k) {
                const Segment& s = segs[k];
                int i0 = (int)floorf((fminf(s.x0, s.x1) - reach) / size);
                int i1 = (int)floorf((fmaxf(s.x0, s.x1) + reach) / size);
                int j0 = (int)floorf((fminf(s.y0, s.y1) - reach) / size);
                int j1 = (int)floorf((fmaxf(s.y0, s.y1) + reach) / size);
                i0 = i0 < 0 ? 0 : i0;
                j0 = j0 < 0 ? 0 : j0;
                i1 = i1 >= bw ? bw - 1 : i1;
                j1 = j1 >= bh ? bh - 1 : j1;
                for (int j = j0; j <= j1; ++j) {
                    for (int i = i0; i <= i1; ++i) {
                        if (pass == 0) counts[j * bw + i]++;
                        else items[fill[j * bw + i]++] = (int)k;
                    }
                }
            }
        }
    }
};

// Topographic wetness index ln(A / tan(beta)) per cell: tan(beta) is the
// steepest descent to an 8-neighbor on the unfilled heights, in cells,
// floored at epsilon (pits and flats). A centered gradient would read a
// sharp crest as flat; the steepest descent is the slope its water leaves by.
void write_twi(const Surface& s, const std::vector<double>& A, const vnoise_twi_t* tp, float* out) {
    const Grid& g = s.g;
    const int n = g.n;
    const double Z = (double)tp->relief * (double)(g.mw > g.mh ? g.mw : g.mh);
    const double eps = tp->epsilon > 0.0f ? tp->epsilon : 1e-3;
    std::vector<double> t(n);
    double lo = 1e300, hi = -1e300;
    for (int c = 0; c < n; ++c) {
        double tanb = 0.0;
        for (int k = 0; k < 8; ++k) {
            int nb;
            if (!g.neighbor(c, k, &nb)) continue;
            const double d = (s.H[c] - s.H[nb]) * Z / NDIST[k];
            tanb = d > tanb ? d : tanb;
        }
        // A cell without rain (rain matrix 0) still drains itself: the area
        // is floored at a thousandth of a cell to keep the log finite.
        const double v = log((A[c] > 1e-3 ? A[c] : 1e-3) / (tanb > eps ? tanb : eps));
        t[c] = v;
        lo = v < lo ? v : lo;
        hi = v > hi ? v : hi;
    }
    for (int k = 0; k < n; ++k) {
        double v;
        if (tp->range > 0.0f) v = t[k] / tp->range;
        else v = hi > lo ? (t[k] - lo) / (hi - lo) : 0.0;
        out[k] = clamp01((float)v);
    }
}

void flow_impl(const float* m, int w, int h, const vnoise_flow_t* fp, const vnoise_twi_t* tp,
               const float* rain, const vnoise_flow_out_t* out, float* twi) {
    Surface s;
    build_surface(m, w, h, fp->sea_level, fp->outlets, s);
    const int n = s.g.n;
    if (out->flow || twi) {
        std::vector<double> A;
        if (fp->method == VNOISE_FLOW_MFD) {
            accumulate_mfd(s, rain, fp->exponent, A);
        } else {
            std::vector<int> recv, order;
            accumulate_d8(s, rain, recv, order, A);
        }
        if (out->flow) write_flow(A, n, fp->scale, fp->range, out->flow);
        if (twi) write_twi(s, A, tp, twi);
    }
    if (out->filled) {
        for (int k = 0; k < n; ++k) out->filled[k] = clamp01((float)s.F[k]);
    }
    if (out->lake) {
        for (int k = 0; k < n; ++k) out->lake[k] = s.F[k] - s.H[k] > (double)fp->lake_depth ? 1.0f : 0.0f;
    }
}

} // namespace

extern "C" VNOISE_API void vnoise_flow(const float* m, int w, int h, const vnoise_flow_t* fp,
                                       const float* rain, const vnoise_flow_out_t* out) {
    if (!m || !fp || !out || w <= 0 || h <= 0) return;
    flow_impl(m, w, h, fp, 0, rain, out, 0);
}

extern "C" VNOISE_API void vnoise_flow_twi(const float* m, int w, int h, const vnoise_flow_t* fp,
                                           const vnoise_twi_t* tp, const float* rain,
                                           const vnoise_flow_out_t* out, float* twi) {
    if (!m || !fp || !out || w <= 0 || h <= 0) return;
    flow_impl(m, w, h, fp, tp, rain, out, tp ? twi : 0);
}

extern "C" VNOISE_API int vnoise_river_network(float* height, int w, int h, const vnoise_network_t* np,
                                               const float* rain, const vnoise_network_out_t* out) {
    if (!height || !np || w <= 0 || h <= 0) return 0;
    Surface s;
    build_surface(height, w, h, np->sea_level, np->outlets, s);
    const Grid& g = s.g;
    const int n = g.n;
    std::vector<int> recv, order;
    std::vector<double> A;
    accumulate_d8(s, rain, recv, order, A);
    const double min_flow = np->min_flow > 0.0f ? np->min_flow : 1.0;
    const double sea = np->sea_level;

    // Channel cells: enough flow, not under the sea. A channel cell's
    // receiver has more flow, so it is a channel cell too unless it is sea.
    std::vector<unsigned char> channel(n, 0);
    std::vector<int> cells;
    for (int k = 0; k < n; ++k) {
        if (A[k] >= min_flow && s.H[k] >= sea) {
            channel[k] = 1;
            cells.push_back(k);
        }
    }
    std::sort(cells.begin(), cells.end(), [&A](int a, int b) { return A[a] > A[b] || (A[a] == A[b] && a < b); });
    // Donor lists (CSR) of the channel cells.
    std::vector<int> dstart(n + 1, 0), donors;
    for (int k = 0; k < n; ++k) {
        if (channel[k] && recv[k] >= 0) dstart[recv[k] + 1]++;
    }
    for (int k = 0; k < n; ++k) dstart[k + 1] += dstart[k];
    donors.assign(dstart[n], 0);
    {
        std::vector<int> fill(dstart.begin(), dstart.end() - 1);
        for (int k = 0; k < n; ++k) {
            if (channel[k] && recv[k] >= 0) donors[fill[recv[k]]++] = k;
        }
    }

    // Rivers, main stems first: from the unassigned channel cell with the
    // most flow, up the largest unassigned donor to a head; downstream it
    // ends at its receiver (an outlet or a cell of an earlier river).
    std::vector<int> owner(n, -1);       // river carved through the cell (-2: skipped)
    std::vector<float> cell_bed(n, -1.0f); // bed of the river at its cells
    std::vector<Segment> segs;
    std::vector<std::vector<float> > lines_x, lines_y, lines_w;
    float wmax = 0.5f;
    const int min_len = np->min_length > 1 ? np->min_length : 2;
    int rivers = 0;
    for (size_t t = 0; t < cells.size(); ++t) {
        const int c0 = cells[t];
        if (owner[c0] != -1) continue;
        std::vector<int> chain(1, c0);
        owner[c0] = -3;
        for (int cur = c0;;) {
            int best = -1;
            for (int k = dstart[cur]; k < dstart[cur + 1]; ++k) {
                const int d = donors[k];
                if (owner[d] != -1) continue;
                if (best < 0 || A[d] > A[best]) best = d;
            }
            if (best < 0) break;
            owner[best] = -3;
            chain.push_back(best);
            cur = best;
        }
        std::reverse(chain.begin(), chain.end());
        const int down = recv[c0];
        const bool junction = down >= 0 && owner[down] >= 0;
        if (down >= 0) chain.push_back(down);
        const int own_cells = (int)chain.size() - (down >= 0 ? 1 : 0);
        if (own_cells < min_len) {
            for (int k = 0; k < own_cells; ++k) owner[chain[k]] = -2;
            continue;
        }
        const int id = rivers++;
        // Raw profile per cell: lake surface height, a bed that never rises,
        // width and depth from the flow.
        const size_t m = chain.size();
        std::vector<std::vector<double> > attrs(4, std::vector<double>(m));
        double run = 1e30;
        const double junction_bed = junction ? (double)cell_bed[down] : -1.0;
        for (size_t k = 0; k < m; ++k) {
            const int c = chain[k];
            const double grow = sqrt(fmax(0.0, A[c] / min_flow - 1.0));
            double wd = np->width0 + np->width_k * grow;
            wd = wd > np->max_width ? np->max_width : wd;
            wd = wd < 0.5 ? 0.5 : wd;
            double depth = np->depth0 + np->depth_k * grow;
            depth = depth > np->max_depth ? np->max_depth : depth;
            double b = s.F[c] - depth;
            b = b < 0.0 ? 0.0 : b;
            b = b > run ? run : b;
            run = b;
            attrs[0][k] = (double)(c % w) + 0.5;
            attrs[1][k] = (double)(c / w) + 0.5;
            attrs[2][k] = b;
            attrs[3][k] = wd;
        }
        if (junction) {
            // A tributary meets the stem at the stem's bed and never digs
            // below it; max with a constant keeps the bed non-increasing.
            attrs[2][m - 1] = junction_bed;
            for (size_t k = 0; k < m; ++k) attrs[2][k] = attrs[2][k] < junction_bed ? junction_bed : attrs[2][k];
        }
        for (size_t k = 0; k + (junction ? 1 : 0) < m; ++k) {
            const int c = chain[k];
            if (k < (size_t)own_cells) {
                owner[c] = id;
                cell_bed[c] = (float)attrs[2][k];
            }
        }
        chaikin(attrs, np->smooth > 0 ? (np->smooth > 4 ? 4 : np->smooth) : 0);
        const size_t q = attrs[0].size();
        lines_x.push_back(std::vector<float>(q));
        lines_y.push_back(std::vector<float>(q));
        lines_w.push_back(std::vector<float>(q));
        for (size_t k = 0; k < q; ++k) {
            lines_x.back()[k] = (float)attrs[0][k];
            lines_y.back()[k] = (float)attrs[1][k];
            lines_w.back()[k] = (float)attrs[3][k];
            wmax = fmaxf(wmax, (float)attrs[3][k]);
            if (k + 1 < q) {
                Segment sg;
                sg.x0 = (float)attrs[0][k];
                sg.y0 = (float)attrs[1][k];
                sg.x1 = (float)attrs[0][k + 1];
                sg.y1 = (float)attrs[1][k + 1];
                sg.b0 = (float)attrs[2][k];
                sg.b1 = (float)attrs[2][k + 1];
                sg.h0 = 0.5f * (float)attrs[3][k];
                sg.h1 = 0.5f * (float)attrs[3][k + 1];
                segs.push_back(sg);
            }
        }
    }

    // Lakes crossed by a river: lake cells connected to a channel cell.
    std::vector<unsigned char> lake(n, 0);
    {
        std::vector<int> stack;
        for (int k = 0; k < n; ++k) {
            if (owner[k] >= 0 && s.F[k] - s.H[k] > (double)np->lake_depth) {
                lake[k] = 1;
                stack.push_back(k);
            }
        }
        while (!stack.empty()) {
            const int c = stack.back();
            stack.pop_back();
            for (int k = 0; k < 8; ++k) {
                int nb;
                if (!g.neighbor(c, k, &nb) || lake[nb]) continue;
                if (s.F[nb] - s.H[nb] > (double)np->lake_depth) {
                    lake[nb] = 1;
                    stack.push_back(nb);
                }
            }
        }
    }
    float* mask = out ? out->mask : 0;
    for (int k = 0; k < n; ++k) {
        if (!lake[k]) continue;
        if (np->fill_lakes) height[k] = clamp01((float)s.F[k]);
        if (mask && mask[k] < 0.5f) mask[k] = 0.5f;
    }

    // Carve every channel and its valley, nearest segment per cell.
    if (!segs.empty()) {
        const float bank = np->bank > 0.0f ? np->bank : 1.0f;
        const float valley = np->valley > 0.0f ? np->valley : 0.0f;
        const float reach = 0.5f * wmax + fmaxf(valley, bank) + 1.0f;
        const float shape = np->valley_shape > 0.0f ? np->valley_shape : 1.0f;
        SegmentIndex index;
        index.build(segs, w, h, reach);
        for (int bj = 0; bj < index.bh; ++bj) {
            for (int bi = 0; bi < index.bw; ++bi) {
                const int b = bj * index.bw + bi;
                if (index.start[b] == index.start[b + 1]) continue;
                const int i0 = (int)floorf((float)bi * index.size), j0 = (int)floorf((float)bj * index.size);
                const int i1 = std::min(w - 1, (int)floorf((float)(bi + 1) * index.size) - 1);
                const int j1 = std::min(h - 1, (int)floorf((float)(bj + 1) * index.size) - 1);
                for (int j = j0; j <= j1; ++j) {
                    for (int i = i0; i <= i1; ++i) {
                        const float px = (float)i + 0.5f, py = (float)j + 0.5f;
                        float best = 1e30f, bt = 0.0f;
                        int bs = -1;
                        for (int it = index.start[b]; it < index.start[b + 1]; ++it) {
                            const Segment& sg = segs[index.items[it]];
                            const float ex = sg.x1 - sg.x0, ey = sg.y1 - sg.y0;
                            const float len2 = ex * ex + ey * ey;
                            float tt = len2 > 0.0f ? ((px - sg.x0) * ex + (py - sg.y0) * ey) / len2 : 0.0f;
                            tt = tt < 0.0f ? 0.0f : (tt > 1.0f ? 1.0f : tt);
                            const float qx = sg.x0 + tt * ex - px, qy = sg.y0 + tt * ey - py;
                            const float d2 = qx * qx + qy * qy;
                            if (d2 < best) {
                                best = d2;
                                bs = index.items[it];
                                bt = tt;
                            }
                        }
                        if (bs < 0) continue;
                        const float d = sqrtf(best);
                        if (d > reach) continue;
                        const Segment& sg = segs[bs];
                        const float bed = sg.b0 + bt * (sg.b1 - sg.b0);
                        const float half = sg.h0 + bt * (sg.h1 - sg.h0);
                        float& cell = height[j * w + i];
                        if (cell > bed) {
                            const float sv = smoothstep(half, half + valley, d);
                            const float prof = sv >= 1.0f ? 1.0f : (sv <= 0.0f ? 0.0f : powf(sv, shape));
                            cell = clamp01(bed + (cell - bed) * prof);
                        }
                        if (mask) {
                            float mv = 0.0f;
                            if (d <= half) mv = 1.0f;
                            else if (d < half + bank) mv = 1.0f - (d - half) / bank;
                            if (mv > mask[j * w + i]) mask[j * w + i] = mv;
                        }
                    }
                }
            }
        }
    }

    if (out && out->flow) write_flow(A, n, VNOISE_FLOW_LOG, 0.0f, out->flow);
    if (out && out->start && out->count && out->xy) {
        int used = 0;
        for (int r = 0; r < rivers && r < out->max_rivers; ++r) {
            const int q = (int)lines_x[r].size();
            if (used + q > out->max_points) {
                out->start[r] = used;
                out->count[r] = 0;
                continue;
            }
            out->start[r] = used;
            out->count[r] = q;
            for (int k = 0; k < q; ++k) {
                out->xy[2 * (used + k)] = lines_x[r][k];
                out->xy[2 * (used + k) + 1] = lines_y[r][k];
                if (out->width) out->width[used + k] = lines_w[r][k];
            }
            used += q;
        }
    }
    return rivers;
}
