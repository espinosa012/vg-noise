#include <cmath>
#include <vector>
#include "vnoise/internal.h"

// Particle-based erosion on a matrix: hydraulic erosion by seeded droplets
// that carry sediment down the slope, and thermal (talus) erosion that moves
// material off slopes steeper than a critical angle. Heights are worked in
// cells (value * relief * max(w, h)) so the parameters do not depend on the
// matrix resolution.

namespace {

inline float clamp01(float v) {
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

// splitmix64-based uniform float in [0, 1).
inline float next_unit(unsigned long long* st) {
    return (float)(vnoise::splitmix64(st) >> 40) * (1.0f / 16777216.0f);
}

// Height and gradient of the scaled heights at index-space point (x, y),
// bilinear between the four nodes around it (0 <= x < w - 1, same for y).
inline float height_grad(const std::vector<float>& S, int w, float x, float y, float* gx,
                         float* gy) {
    const int i = (int)x, j = (int)y;
    const float fx = x - (float)i, fy = y - (float)j;
    const int k = j * w + i;
    const float a = S[k], b = S[k + 1], c = S[k + w], d = S[k + w + 1];
    *gx = (b - a) * (1.0f - fy) + (d - c) * fy;
    *gy = (c - a) * (1.0f - fx) + (d - b) * fx;
    return a * (1.0f - fx) * (1.0f - fy) + b * fx * (1.0f - fy) + c * (1.0f - fx) * fy + d * fx * fy;
}

// Adds amount to the four nodes around (x, y), weighted bilinearly.
inline void deposit_at(std::vector<float>& S, int w, float x, float y, float amount) {
    const int i = (int)x, j = (int)y;
    const float fx = x - (float)i, fy = y - (float)j;
    const int k = j * w + i;
    S[k] += amount * (1.0f - fx) * (1.0f - fy);
    S[k + 1] += amount * fx * (1.0f - fy);
    S[k + w] += amount * (1.0f - fx) * fy;
    S[k + w + 1] += amount * fx * fy;
}

// Writes the scaled heights back as values, adding each cell's change to its
// original value so untouched cells keep it exactly (only clamped to 0..1).
void write_back(float* m, const std::vector<float>& S, const std::vector<float>& S0, int n, float Z) {
    for (int k = 0; k < n; ++k) {
        const float v = clamp01(m[k]);
        m[k] = S[k] == S0[k] ? v : clamp01(v + (S[k] - S0[k]) / Z);
    }
}

// Normalized change map: 0.5 + 0.5 * dz / max|dz|.
void write_change(const float* before, const float* after, int n, float* change_out) {
    float maxd = 0.0f;
    for (int k = 0; k < n; ++k) maxd = fmaxf(maxd, fabsf(after[k] - before[k]));
    for (int k = 0; k < n; ++k) {
        change_out[k] = maxd > 0.0f ? clamp01(0.5f + 0.5f * (after[k] - before[k]) / maxd) : 0.5f;
    }
}

} // namespace

extern "C" VNOISE_API void vnoise_erode_hydraulic(float* m, int w, int h, const vnoise_hydraulic_t* hp,
                                                  const float* hardness, const float* rain,
                                                  float* change_out) {
    if (!m || !hp || w < 2 || h < 2) return;
    const int n = w * h;
    const float Z = (hp->relief > 0.0f ? hp->relief : 0.05f) * (float)(w > h ? w : h);
    const float sea = hp->sea_level * Z;
    std::vector<float> S(n), before;
    for (int k = 0; k < n; ++k) S[k] = clamp01(m[k]) * Z;
    const std::vector<float> S0(S);
    if (change_out) before.assign(m, m + n);

    // Erosion brush: offsets within `radius` cells, weight radius - distance.
    const int R = hp->radius > 0 ? (hp->radius > 8 ? 8 : hp->radius) : 1;
    std::vector<int> bdx, bdy;
    std::vector<float> bw;
    for (int dy = -R; dy <= R; ++dy) {
        for (int dx = -R; dx <= R; ++dx) {
            const float d = sqrtf((float)(dx * dx + dy * dy));
            if (d < (float)R) {
                bdx.push_back(dx);
                bdy.push_back(dy);
                bw.push_back((float)R - d);
            }
        }
    }
    const int nb = (int)bw.size();

    const float inertia = clamp01(hp->inertia);
    const float evaporation = clamp01(hp->evaporation);
    const int lifetime = hp->lifetime > 0 ? hp->lifetime : 30;
    unsigned long long st = hp->seed ^ 0x9E3779B97F4A7C15ULL;
    for (int drop = 0; drop < hp->droplets; ++drop) {
        float x = next_unit(&st) * (float)(w - 1);
        float y = next_unit(&st) * (float)(h - 1);
        const float accept = next_unit(&st);
        if (rain) {
            const int ci = (int)(x + 0.5f), cj = (int)(y + 0.5f);
            if (accept >= rain[cj * w + ci]) continue;
        }
        float dirx = 0.0f, diry = 0.0f, speed = 1.0f, water = 1.0f, sediment = 0.0f;
        for (int life = 0; life < lifetime; ++life) {
            float gx, gy;
            const float h0 = height_grad(S, w, x, y, &gx, &gy);
            if (h0 < sea) {
                deposit_at(S, w, x, y, sediment);
                break;
            }
            dirx = dirx * inertia - gx * (1.0f - inertia);
            diry = diry * inertia - gy * (1.0f - inertia);
            float len = sqrtf(dirx * dirx + diry * diry);
            if (len < 1e-9f) {
                const float a = next_unit(&st) * 6.2831853f;
                dirx = cosf(a);
                diry = sinf(a);
            } else {
                dirx /= len;
                diry /= len;
            }
            const float nx = x + dirx, ny = y + diry;
            if (nx < 0.0f || ny < 0.0f || nx >= (float)(w - 1) || ny >= (float)(h - 1)) {
                // Leaving the matrix: drop the load at the edge, so material
                // is not carried out of the map.
                deposit_at(S, w, x, y, sediment);
                sediment = 0.0f;
                break;
            }
            float ngx, ngy;
            const float h1 = height_grad(S, w, nx, ny, &ngx, &ngy);
            const float dh = h1 - h0;
            const float cap = fmaxf(-dh, hp->min_slope) * speed * water * hp->capacity;
            if (sediment > cap || dh > 0.0f) {
                // Uphill: fill the step behind (at most what is carried);
                // otherwise drop the excess over capacity.
                const float amount = dh > 0.0f ? fminf(dh, sediment) : (sediment - cap) * hp->deposit;
                sediment -= amount;
                deposit_at(S, w, x, y, amount);
            } else {
                const float amount = fminf((cap - sediment) * hp->erode, -dh);
                const int ci = (int)x, cj = (int)y;
                float wsum = 0.0f;
                for (int b = 0; b < nb; ++b) {
                    const int i = ci + bdx[b], j = cj + bdy[b];
                    if (i >= 0 && j >= 0 && i < w && j < h) wsum += bw[b];
                }
                for (int b = 0; b < nb && wsum > 0.0f; ++b) {
                    const int i = ci + bdx[b], j = cj + bdy[b];
                    if (i < 0 || j < 0 || i >= w || j >= h) continue;
                    const int k = j * w + i;
                    float dz = amount * bw[b] / wsum;
                    if (hardness) dz *= 1.0f - clamp01(hardness[k]);
                    if (dz > S[k]) dz = S[k];
                    S[k] -= dz;
                    sediment += dz;
                }
            }
            speed = sqrtf(fmaxf(0.0f, speed * speed - dh * hp->gravity));
            water *= 1.0f - evaporation;
            x = nx;
            y = ny;
            if (life == lifetime - 1) deposit_at(S, w, x, y, sediment);  // dries out
        }
    }
    write_back(m, S, S0, n, Z);
    if (change_out) write_change(before.data(), m, n, change_out);
}

extern "C" VNOISE_API void vnoise_erode_thermal(float* m, int w, int h, const vnoise_thermal_t* tp,
                                                const float* hardness) {
    if (!m || !tp || w <= 0 || h <= 0) return;
    static const int DX[8] = { 1, -1, 0, 0, 1, -1, 1, -1 };
    static const int DY[8] = { 0, 0, 1, -1, 1, 1, -1, -1 };
    static const float DIST[8] = { 1, 1, 1, 1, 1.41421356f, 1.41421356f, 1.41421356f, 1.41421356f };
    const int n = w * h;
    const float Z = (tp->relief > 0.0f ? tp->relief : 0.05f) * (float)(w > h ? w : h);
    const float talus = tanf(fminf(fmaxf(tp->talus, 0.0f), 89.0f) * 3.14159265f / 180.0f);
    const float rate = clamp01(tp->rate);
    std::vector<float> S(n), delta(n);
    for (int k = 0; k < n; ++k) S[k] = clamp01(m[k]) * Z;
    const std::vector<float> S0(S);
    for (int it = 0; it < tp->iterations; ++it) {
        std::fill(delta.begin(), delta.end(), 0.0f);
        bool moved = false;
        for (int j = 0; j < h; ++j) {
            for (int i = 0; i < w; ++i) {
                const int c = j * w + i;
                float excess[8];
                float total = 0.0f, best = 0.0f, best_dist = 1.0f;
                for (int k = 0; k < 8; ++k) {
                    excess[k] = 0.0f;
                    const int ni = i + DX[k], nj = j + DY[k];
                    if (ni < 0 || nj < 0 || ni >= w || nj >= h) continue;
                    const float e = (S[c] - S[nj * w + ni]) / DIST[k] - talus;
                    if (e <= 0.0f) continue;
                    excess[k] = e;
                    total += e;
                    if (e > best) {
                        best = e;
                        best_dist = DIST[k];
                    }
                }
                if (total <= 0.0f) continue;
                // Half the steepest excess drop: the most that can move
                // without reversing the slope to that neighbor.
                float amount = rate * 0.5f * best * best_dist;
                if (hardness) amount *= 1.0f - clamp01(hardness[c]);
                if (amount <= 0.0f) continue;
                moved = true;
                delta[c] -= amount;
                for (int k = 0; k < 8; ++k) {
                    if (excess[k] > 0.0f) delta[(j + DY[k]) * w + (i + DX[k])] += amount * excess[k] / total;
                }
            }
        }
        if (!moved) break;
        for (int k = 0; k < n; ++k) S[k] += delta[k];
    }
    write_back(m, S, S0, n, Z);
}
