#include <cmath>
#include "vnoise/internal.h"

namespace vnoise {

static const float SQRT3 = 1.7320508075688772f;
static const float SKEW2 = (SQRT3 - 1.0f) / 2.0f;
static const float UNSKEW2 = (3.0f - SQRT3) / 6.0f;

static const float SKEW3 = 1.0f / 3.0f;
static const float UNSKEW3 = 1.0f / 6.0f;

static const int GRAD3[12][3] = {
    { 1,  1, 0}, {-1,  1, 0}, { 1, -1, 0}, {-1, -1, 0},
    { 1,  0, 1}, {-1,  0, 1}, { 1,  0,-1}, {-1,  0,-1},
    { 0,  1, 1}, { 0, -1, 1}, { 0,  1,-1}, { 0, -1,-1}
};

// 2D gradients: 16 unit vectors evenly spaced around the circle (offset by
// half a step so none is axis-aligned). An isotropic set avoids the long
// straight diagonal/horizontal streaks of a reduced gradient set.
static const float GRAD2[16][2] = {
    {0.980785280f, 0.195090322f},
    {0.831469612f, 0.555570233f},
    {0.555570233f, 0.831469612f},
    {0.195090322f, 0.980785280f},
    {-0.195090322f, 0.980785280f},
    {-0.555570233f, 0.831469612f},
    {-0.831469612f, 0.555570233f},
    {-0.980785280f, 0.195090322f},
    {-0.980785280f, -0.195090322f},
    {-0.831469612f, -0.555570233f},
    {-0.555570233f, -0.831469612f},
    {-0.195090322f, -0.980785280f},
    {0.195090322f, -0.980785280f},
    {0.555570233f, -0.831469612f},
    {0.831469612f, -0.555570233f},
    {0.980785280f, -0.195090322f}
};

// Output scale so 2D simplex spans approximately [-1, 1] with unit gradients.
static const float SIMPLEX2_SCALE = 99.2f;

static inline int fastfloor(float x) {
    int i = (int)x;
    return (x < 0 && x != i) ? i - 1 : i;
}

float simplex2(const noise_state_t* s, float x, float y) {
    float skew = (x + y) * SKEW2;
    int i = fastfloor(x + skew);
    int j = fastfloor(y + skew);
    float unskew = (i + j) * UNSKEW2;
    float X0 = i - unskew;
    float Y0 = j - unskew;
    float x0 = x - X0;
    float y0 = y - Y0;

    int i1, j1;
    if (x0 > y0) { i1 = 1; j1 = 0; }
    else         { i1 = 0; j1 = 1; }

    float x1 = x0 - i1 + UNSKEW2;
    float y1 = y0 - j1 + UNSKEW2;
    float x2 = x0 - 1.0f + 2.0f * UNSKEW2;
    float y2 = y0 - 1.0f + 2.0f * UNSKEW2;

    int ii = i & 255;
    int jj = j & 255;
    const unsigned int* p = s->perm;
    int gi0 = (int)(p[ii       + p[jj      ]] & 15);
    int gi1 = (int)(p[ii + i1  + p[jj + j1 ]] & 15);
    int gi2 = (int)(p[ii + 1   + p[jj + 1  ]] & 15);

    float n0 = 0, n1 = 0, n2 = 0;
    float t0 = 0.5f - x0 * x0 - y0 * y0;
    if (t0 >= 0) { t0 *= t0; n0 = t0 * t0 * (GRAD2[gi0][0] * x0 + GRAD2[gi0][1] * y0); }
    float t1 = 0.5f - x1 * x1 - y1 * y1;
    if (t1 >= 0) { t1 *= t1; n1 = t1 * t1 * (GRAD2[gi1][0] * x1 + GRAD2[gi1][1] * y1); }
    float t2 = 0.5f - x2 * x2 - y2 * y2;
    if (t2 >= 0) { t2 *= t2; n2 = t2 * t2 * (GRAD2[gi2][0] * x2 + GRAD2[gi2][1] * y2); }

    return SIMPLEX2_SCALE * (n0 + n1 + n2);
}

float simplex3(const noise_state_t* s, float x, float y, float z) {
    if (s == 0) return 0;
    float skew = (x + y + z) * SKEW3;
    int i = fastfloor(x + skew);
    int j = fastfloor(y + skew);
    int k = fastfloor(z + skew);
    float unskew = (i + j + k) * UNSKEW3;
    float X0 = i - unskew, Y0 = j - unskew, Z0 = k - unskew;
    float x0 = x - X0, y0 = y - Y0, z0 = z - Z0;

    int i1, j1, k1, i2, j2, k2;
    if (x0 >= y0) {
        if (y0 >= z0)      { i1=1; j1=0; k1=0;  i2=1; j2=1; k2=0; }
        else if (x0 >= z0) { i1=1; j1=0; k1=0;  i2=1; j2=0; k2=1; }
        else               { i1=0; j1=0; k1=1;  i2=1; j2=0; k2=1; }
    } else {
        if (y0 < z0)       { i1=0; j1=0; k1=1;  i2=0; j2=1; k2=1; }
        else if (x0 < z0)  { i1=0; j1=1; k1=0;  i2=0; j2=1; k2=1; }
        else               { i1=0; j1=1; k1=0;  i2=1; j2=1; k2=0; }
    }

    float x1 = x0 - i1 + UNSKEW3, y1 = y0 - j1 + UNSKEW3, z1 = z0 - k1 + UNSKEW3;
    float x2 = x0 - i2 + 2.0f * UNSKEW3, y2 = y0 - j2 + 2.0f * UNSKEW3, z2 = z0 - k2 + 2.0f * UNSKEW3;
    float x3 = x0 - 1.0f + 3.0f * UNSKEW3, y3 = y0 - 1.0f + 3.0f * UNSKEW3, z3 = z0 - 1.0f + 3.0f * UNSKEW3;

    int ii = i & 255, jj = j & 255, kk = k & 255;
    const unsigned int* p = s->perm;
    int gi0 = (int)(p[ii        + p[jj        + p[kk      ]]] % 12);
    int gi1 = (int)(p[ii + i1   + p[jj + j1   + p[kk + k1 ]]] % 12);
    int gi2 = (int)(p[ii + i2   + p[jj + j2   + p[kk + k2 ]]] % 12);
    int gi3 = (int)(p[ii + 1    + p[jj + 1    + p[kk + 1  ]]] % 12);

    float n0 = 0, n1 = 0, n2 = 0, n3 = 0;
    float t0 = 0.6f - x0*x0 - y0*y0 - z0*z0;
    if (t0 >= 0) { t0 *= t0; n0 = t0 * t0 * (GRAD3[gi0][0]*x0 + GRAD3[gi0][1]*y0 + GRAD3[gi0][2]*z0); }
    float t1 = 0.6f - x1*x1 - y1*y1 - z1*z1;
    if (t1 >= 0) { t1 *= t1; n1 = t1 * t1 * (GRAD3[gi1][0]*x1 + GRAD3[gi1][1]*y1 + GRAD3[gi1][2]*z1); }
    float t2 = 0.6f - x2*x2 - y2*y2 - z2*z2;
    if (t2 >= 0) { t2 *= t2; n2 = t2 * t2 * (GRAD3[gi2][0]*x2 + GRAD3[gi2][1]*y2 + GRAD3[gi2][2]*z2); }
    float t3 = 0.6f - x3*x3 - y3*y3 - z3*z3;
    if (t3 >= 0) { t3 *= t3; n3 = t3 * t3 * (GRAD3[gi3][0]*x3 + GRAD3[gi3][1]*y3 + GRAD3[gi3][2]*z3); }

    return 32.0f * (n0 + n1 + n2 + n3);
}

} // namespace vnoise

extern "C" {

VNOISE_API float simplex2_eval(const noise_state_t* s, float x, float y) {
    if (!s) return 0;
    return vnoise::simplex2(s, x, y);
}

VNOISE_API float simplex3_eval(const noise_state_t* s, float x, float y, float z) {
    if (!s) return 0;
    return vnoise::simplex3(s, x, y, z);
}

}