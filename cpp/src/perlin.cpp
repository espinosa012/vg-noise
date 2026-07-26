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

}