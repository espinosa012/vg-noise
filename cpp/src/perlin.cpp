#include <cmath>
#include "vnoise/internal.h"

namespace vnoise {

float grad2(int hash, float x, float y) {
    switch (hash & 7) {
        case 0: return  x + y;
        case 1: return  x - y;
        case 2: return -x + y;
        case 3: return -x - y;
        case 4: return  x;
        case 5: return -x;
        case 6: return  y;
        case 7: return -y;
    }
    return 0.0f;
}

float grad3(int hash, float x, float y, float z) {
    switch (hash & 15) {
        case 0: return  x + y;
        case 1: return -x + y;
        case 2: return  x - y;
        case 3: return -x - y;
        case 4: return  x + z;
        case 5: return -x + z;
        case 6: return  x - z;
        case 7: return -x - z;
        case 8: return  y + z;
        case 9: return -y + z;
        case 10: return  y - z;
        case 11: return -y - z;
        case 12: return  x + y;
        case 13: return -x + y;
        case 14: return  y - z;
        case 15: return -y - z;
    }
    return 0.0f;
}

} // namespace vnoise

extern "C" {

VNOISE_API float perlin2_eval(const noise_state_t* s, float x, float y) {
    int X = (int)floorf(x) & 255;
    int Y = (int)floorf(y) & 255;
    x -= floorf(x);
    y -= floorf(y);
    float u = vnoise::fade(x);
    float v = vnoise::fade(y);
    const unsigned int* p = s->perm;
    int A  = p[X]   + Y;
    int AA = p[A];
    int AB = p[A + 1];
    int B  = p[X + 1] + Y;
    int BA = p[B];
    int BB = p[B + 1];
    return vnoise::lerp(
        vnoise::lerp(vnoise::grad2((int)p[AA], x,     y),
                    vnoise::grad2((int)p[BA], x - 1, y), u),
        vnoise::lerp(vnoise::grad2((int)p[AB], x,     y - 1),
                    vnoise::grad2((int)p[BB], x - 1, y - 1), u),
        v);
}

VNOISE_API float perlin3_eval(const noise_state_t* s, float x, float y, float z) {
    int X = (int)floorf(x) & 255;
    int Y = (int)floorf(y) & 255;
    int Z = (int)floorf(z) & 255;
    x -= floorf(x); y -= floorf(y); z -= floorf(z);
    float u = vnoise::fade(x);
    float v = vnoise::fade(y);
    float w = vnoise::fade(z);
    const unsigned int* p = s->perm;
    int A  = p[X]   + Y;
    int AA = p[A]     + Z;
    int AB = p[A + 1] + Z;
    int B  = p[X + 1] + Y;
    int BA = p[B]     + Z;
    int BB = p[B + 1] + Z;
    return vnoise::lerp(
        vnoise::lerp(
            vnoise::lerp(vnoise::grad3((int)p[AA],       x,     y,     z),
                        vnoise::grad3((int)p[BA],       x - 1, y,     z), u),
            vnoise::lerp(vnoise::grad3((int)p[AB],       x,     y - 1, z),
                        vnoise::grad3((int)p[BB],       x - 1, y - 1, z), u),
            v),
        vnoise::lerp(
            vnoise::lerp(vnoise::grad3((int)p[AA + 1],   x,     y,     z - 1),
                        vnoise::grad3((int)p[BA + 1],   x - 1, y,     z - 1), u),
            vnoise::lerp(vnoise::grad3((int)p[AB + 1],   x,     y - 1, z - 1),
                        vnoise::grad3((int)p[BB + 1],   x - 1, y - 1, z - 1), u),
            v),
        w);
}


// Gradient vectors matching grad2's eight cases.
static const float PERLIN_G2[8][2] = {
    { 1,  1}, { 1, -1}, {-1,  1}, {-1, -1}, { 1,  0}, {-1,  0}, { 0,  1}, { 0, -1}
};

// 2D Perlin noise with its analytic gradient: with corner values a, b, c, d
// (bottom-left, bottom-right, top-left, top-right) and quintic weights u, v,
// n = a + u (b - a) + v (c - a) + u v (a - b - c + d); the product rule gives
// the gradient through u' = fade'(x) and v' = fade'(y).
VNOISE_API float perlin2_deriv(const noise_state_t* s, float x, float y, float* dx, float* dy) {
    if (!s) {
        if (dx) *dx = 0;
        if (dy) *dy = 0;
        return 0;
    }
    int X = (int)floorf(x) & 255;
    int Y = (int)floorf(y) & 255;
    x -= floorf(x);
    y -= floorf(y);
    float u = vnoise::fade(x);
    float v = vnoise::fade(y);
    float du = 30.0f * x * x * (x * (x - 2.0f) + 1.0f);
    float dv = 30.0f * y * y * (y * (y - 2.0f) + 1.0f);
    const unsigned int* p = s->perm;
    int A  = p[X]   + Y;
    int AA = p[A];
    int AB = p[A + 1];
    int B  = p[X + 1] + Y;
    int BA = p[B];
    int BB = p[B + 1];
    const float* ga = PERLIN_G2[p[AA] & 7];
    const float* gb = PERLIN_G2[p[BA] & 7];
    const float* gc = PERLIN_G2[p[AB] & 7];
    const float* gd = PERLIN_G2[p[BB] & 7];
    float a = vnoise::grad2((int)p[AA], x,     y);
    float b = vnoise::grad2((int)p[BA], x - 1, y);
    float c = vnoise::grad2((int)p[AB], x,     y - 1);
    float d = vnoise::grad2((int)p[BB], x - 1, y - 1);
    float k = a - b - c + d;
    if (dx) *dx = ga[0] + u * (gb[0] - ga[0]) + v * (gc[0] - ga[0]) + u * v * (ga[0] - gb[0] - gc[0] + gd[0])
                  + du * ((b - a) + v * k);
    if (dy) *dy = ga[1] + u * (gb[1] - ga[1]) + v * (gc[1] - ga[1]) + u * v * (ga[1] - gb[1] - gc[1] + gd[1])
                  + dv * ((c - a) + u * k);
    return vnoise::lerp(vnoise::lerp(a, b, u), vnoise::lerp(c, d, u), v);
}

}
