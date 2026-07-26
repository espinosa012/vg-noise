#ifndef VNOISE_H
#define VNOISE_H

#ifdef _WIN32
  #ifdef VNOISE_LIBRARY
    #define VNOISE_API __declspec(dllexport)
  #else
    #define VNOISE_API __declspec(dllimport)
  #endif
#else
  #define VNOISE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    unsigned int perm[512];
    unsigned long long seed;
} noise_state_t;

#define VNOISE_BASE_PERLIN2  0
#define VNOISE_BASE_PERLIN3  1
#define VNOISE_BASE_SIMPLEX2 2
#define VNOISE_BASE_SIMPLEX3 3
#define VNOISE_BASE_WHITE2   4
#define VNOISE_BASE_WHITE3   5

VNOISE_API void noise_init(noise_state_t* s, unsigned long long seed);

VNOISE_API float perlin2_eval(const noise_state_t* s, float x, float y);
VNOISE_API float perlin3_eval(const noise_state_t* s, float x, float y, float z);
VNOISE_API float simplex2_eval(const noise_state_t* s, float x, float y);
VNOISE_API float simplex3_eval(const noise_state_t* s, float x, float y, float z);
VNOISE_API float white2_eval(const noise_state_t* s, int ix, int iy);
VNOISE_API float white3_eval(const noise_state_t* s, int ix, int iy, int iz);

VNOISE_API float fbm2_eval(const noise_state_t* s, int base,
                           float x, float y, int octaves,
                           float lacunarity, float gain);
VNOISE_API float fbm3_eval(const noise_state_t* s, int base,
                           float x, float y, float z, int octaves,
                           float lacunarity, float gain);
VNOISE_API float ridge2_eval(const noise_state_t* s, int base,
                              float x, float y, int octaves,
                              float lacunarity, float gain);
VNOISE_API float ridge3_eval(const noise_state_t* s, int base,
                              float x, float y, float z, int octaves,
                              float lacunarity, float gain);
VNOISE_API float turb2_eval(const noise_state_t* s, int base,
                             float x, float y, int octaves,
                             float lacunarity, float gain);
VNOISE_API float turb3_eval(const noise_state_t* s, int base,
                             float x, float y, float z, int octaves,
                             float lacunarity, float gain);

VNOISE_API void fbm2_fill_grid(const noise_state_t* s, int base,
                               float* out, float ox, float oy,
                               int w, int h, float freq,
                               int octaves, float lac, float gain);
VNOISE_API void ridge2_fill_grid(const noise_state_t* s, int base,
                                  float* out, float ox, float oy,
                                  int w, int h, float freq,
                                  int octaves, float lac, float gain);
VNOISE_API void turb2_fill_grid(const noise_state_t* s, int base,
                                 float* out, float ox, float oy,
                                 int w, int h, float freq,
                                 int octaves, float lac, float gain);

VNOISE_API void fbm3_fill_volume(const noise_state_t* s, int base,
                                  float* out, float ox, float oy, float oz,
                                  int w, int h, int d, float freq,
                                  int octaves, float lac, float gain);
VNOISE_API void ridge3_fill_volume(const noise_state_t* s, int base,
                                    float* out, float ox, float oy, float oz,
                                    int w, int h, int d, float freq,
                                    int octaves, float lac, float gain);
VNOISE_API void turb3_fill_volume(const noise_state_t* s, int base,
                                   float* out, float ox, float oy, float oz,
                                   int w, int h, int d, float freq,
                                   int octaves, float lac, float gain);

VNOISE_API void fbm2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                          unsigned char* out, int w, int h,
                                          float ox, float oy, float freq,
                                          int octaves, float lac, float gain,
                                          float lo, float hi,
                                          unsigned char r, unsigned char g,
                                          unsigned char b, unsigned char a);
VNOISE_API void ridge2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                            unsigned char* out, int w, int h,
                                            float ox, float oy, float freq,
                                            int octaves, float lac, float gain,
                                            float lo, float hi,
                                            unsigned char r, unsigned char g,
                                            unsigned char b, unsigned char a);
VNOISE_API void turb2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                           unsigned char* out, int w, int h,
                                           float ox, float oy, float freq,
                                           int octaves, float lac, float gain,
                                           float lo, float hi,
                                           unsigned char r, unsigned char g,
                                           unsigned char b, unsigned char a);

#ifdef __cplusplus
}
#endif

#endif