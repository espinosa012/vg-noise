#include "vnoise/internal.h"

#define VNOISE_FILL_GRID_2D(NAME, MODE)                                      \
extern "C" VNOISE_API void NAME(const noise_state_t* s, int base,            \
                                float* out, float ox, float oy,              \
                                int w, int h, float freq,                    \
                                int octaves, float lac, float gain) {        \
    if (!s || !out || w <= 0 || h <= 0) return;                              \
    for (int j = 0; j < h; ++j) {                                            \
        float y = oy + (float)j * freq;                                     \
        for (int i = 0; i < w; ++i) {                                        \
            float x = ox + (float)i * freq;                                 \
            out[j * w + i] =                                                 \
                vnoise::fbm_sample(s, base, x, y, octaves, lac, gain, MODE); \
        }                                                                   \
    }                                                                       \
}

#define VNOISE_FILL_VOL_3D(NAME, MODE)                                                        \
extern "C" VNOISE_API void NAME(const noise_state_t* s, int base,                             \
                                float* out, float ox, float oy, float oz,                   \
                                int w, int h, int d, float freq,                              \
                                int octaves, float lac, float gain) {                        \
    if (!s || !out || w <= 0 || h <= 0 || d <= 0) return;                                     \
    for (int k = 0; k < d; ++k) {                                                             \
        float z = oz + (float)k * freq;                                                      \
        for (int j = 0; j < h; ++j) {                                                          \
            float y = oy + (float)j * freq;                                                   \
            for (int i = 0; i < w; ++i) {                                                      \
                float x = ox + (float)i * freq;                                               \
                out[(k * h + j) * w + i] =                                                    \
                    vnoise::fbm_sample3(s, base, x, y, z, octaves, lac, gain, MODE);         \
            }                                                                                  \
        }                                                                                      \
    }                                                                                          \
}

VNOISE_FILL_GRID_2D(fbm2_fill_grid,   vnoise::FBM)
VNOISE_FILL_GRID_2D(ridge2_fill_grid, vnoise::RIDGE)
VNOISE_FILL_GRID_2D(turb2_fill_grid,  vnoise::TURB)

VNOISE_FILL_VOL_3D(fbm3_fill_volume,   vnoise::FBM)
VNOISE_FILL_VOL_3D(ridge3_fill_volume, vnoise::RIDGE)
VNOISE_FILL_VOL_3D(turb3_fill_volume,  vnoise::TURB)