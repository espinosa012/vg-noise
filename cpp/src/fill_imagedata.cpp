#include "vnoise/internal.h"

#define VNOISE_FILL_IMG_2D(NAME, MODE)                                                       \
extern "C" VNOISE_API void NAME(const noise_state_t* s, int base,                             \
                                unsigned char* out, int w, int h,                            \
                                float ox, float oy, float freq,                              \
                                int octaves, float lac, float gain,                          \
                                float lo, float hi,                                           \
                                unsigned char r, unsigned char g,                            \
                                unsigned char b, unsigned char a) {                           \
    if (!s || !out || w <= 0 || h <= 0) return;                                              \
    const float inv = 1.0f / (hi - lo);                                                     \
    for (int j = 0; j < h; ++j) {                                                            \
        float y = oy + (float)j * freq;                                                      \
        for (int i = 0; i < w; ++i) {                                                         \
            float x = ox + (float)i * freq;                                                  \
            float n = vnoise::fbm_sample(s, base, x, y, octaves, lac, gain, MODE);           \
            float t = (n - lo) * inv;                                                        \
            if (t < 0.0f) t = 0.0f; else if (t > 1.0f) t = 1.0f;                              \
            unsigned char* px = out + (j * w + i) * 4;                                         \
            px[0] = (unsigned char)(r * t);                                                  \
            px[1] = (unsigned char)(g * t);                                                  \
            px[2] = (unsigned char)(b * t);                                                  \
            px[3] = a;                                                                       \
        }                                                                                    \
    }                                                                                        \
}

VNOISE_FILL_IMG_2D(fbm2_fill_imagedata_rgba8,   vnoise::FBM)
VNOISE_FILL_IMG_2D(ridge2_fill_imagedata_rgba8, vnoise::RIDGE)
VNOISE_FILL_IMG_2D(turb2_fill_imagedata_rgba8,  vnoise::TURB)

// Same pixel writes as VNOISE_FILL_IMG_2D, with t taken from an op chain
// (always clamped; data is the LUT pool) instead of the lo/hi range.
#define VNOISE_FILL_IMG_OPS_2D(NAME, MODE)                                                   \
extern "C" VNOISE_API void NAME(const noise_state_t* s, int base,                             \
                                unsigned char* out, int w, int h,                            \
                                float ox, float oy, float freq,                              \
                                int octaves, float lac, float gain,                          \
                                const vnoise_op_t* ops, int n, const float* data,            \
                                unsigned char r, unsigned char g,                            \
                                unsigned char b, unsigned char a) {                           \
    if (!s || !out || w <= 0 || h <= 0) return;                                              \
    if (!ops) n = 0;                                                                         \
    for (int j = 0; j < h; ++j) {                                                            \
        float y = oy + (float)j * freq;                                                      \
        for (int i = 0; i < w; ++i) {                                                         \
            float x = ox + (float)i * freq;                                                  \
            float n0 = vnoise::fbm_sample(s, base, x, y, octaves, lac, gain, MODE);          \
            float t = vnoise::apply_ops(n0, ops, n, data, 1);                                \
            unsigned char* px = out + (j * w + i) * 4;                                         \
            px[0] = (unsigned char)(r * t);                                                  \
            px[1] = (unsigned char)(g * t);                                                  \
            px[2] = (unsigned char)(b * t);                                                  \
            px[3] = a;                                                                       \
        }                                                                                    \
    }                                                                                        \
}

VNOISE_FILL_IMG_OPS_2D(fbm2_fill_imagedata_ops_rgba8,   vnoise::FBM)
VNOISE_FILL_IMG_OPS_2D(ridge2_fill_imagedata_ops_rgba8, vnoise::RIDGE)
VNOISE_FILL_IMG_OPS_2D(turb2_fill_imagedata_ops_rgba8,  vnoise::TURB)
