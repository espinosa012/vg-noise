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

/* Fills out[j * w + i] with white2_eval(s, ox + i, oy + j) for a w x h block
 * of integer cells (bit-identical to the per-cell call, one hash per value). */
VNOISE_API void white2_fill_grid(const noise_state_t* s, float* out,
                                 int ox, int oy, int w, int h);

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

/* Value operations: an ordered chain applied to noise values after sampling.
 * Each op reads up to four parameters from p[]; unused entries are ignored.
 *   REMAP    (v - p[0]) / (p[1] - p[0])   (0 when p[1] == p[0])
 *   SCALE    v * p[0]
 *   OFFSET   v + p[0]
 *   CONTRAST (v - p[1]) * p[0] + p[1]     (factor p[0] around pivot p[1])
 *   LUT      look-up table of p[1] samples starting at data[p[0]], spread
 *            evenly over [0, 1]: v is clamped to [0, 1] and interpolated
 *            linearly between the two neighboring samples (a table with a
 *            single sample is constant). Offsets and counts are integers
 *            stored as floats (exact below 2^24).
 *   INVERT     1 - v
 *   THRESHOLD  v >= p[0] ? 1 : 0
 *   SMOOTHSTEP t = clamp01((v - p[0]) / (p[1] - p[0])), t * t * (3 - 2t)
 *              (a threshold at p[0] when p[1] == p[0])
 *   GAMMA      max(v, 0) ^ p[0]
 *   QUANTIZE   n = floor(p[0]) >= 2 levels: min(floor(clamp01(v) * n), n - 1)
 *              / (n - 1); v is unchanged for n < 2
 *   CLAMP      min(max(v, p[0]), p[1]) (an explicit intermediate clamp)
 * Ops run in array order on unclamped values; only the final result is
 * optionally clamped to [0, 1]. Unknown op ids leave the value unchanged,
 * and so does a LUT op when data is NULL.
 *
 * `data` is the float pool that LUT ops index into (NULL when the chain has
 * no LUT op). */
#define VNOISE_OP_REMAP    0
#define VNOISE_OP_SCALE    1
#define VNOISE_OP_OFFSET   2
#define VNOISE_OP_CONTRAST 3
#define VNOISE_OP_LUT      4
#define VNOISE_OP_INVERT     5
#define VNOISE_OP_THRESHOLD  6
#define VNOISE_OP_SMOOTHSTEP 7
#define VNOISE_OP_GAMMA      8
#define VNOISE_OP_QUANTIZE   9
#define VNOISE_OP_CLAMP      10

typedef struct {
    int op;
    float p[4];
} vnoise_op_t;

VNOISE_API float vnoise_apply_ops(float v, const vnoise_op_t* ops, int n,
                                  const float* data, int clamp01);
VNOISE_API void vnoise_map_buffer(float* buf, int count,
                                  const vnoise_op_t* ops, int n,
                                  const float* data, int clamp01);

/* Like *_fill_imagedata_rgba8, but each pixel is t = clamp01(chain(noise))
 * with the op chain (ops, n, data) in place of the lo/hi range. */
VNOISE_API void fbm2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                              unsigned char* out, int w, int h,
                                              float ox, float oy, float freq,
                                              int octaves, float lac, float gain,
                                              const vnoise_op_t* ops, int n, const float* data,
                                              unsigned char r, unsigned char g,
                                              unsigned char b, unsigned char a);
VNOISE_API void ridge2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                                unsigned char* out, int w, int h,
                                                float ox, float oy, float freq,
                                                int octaves, float lac, float gain,
                                                const vnoise_op_t* ops, int n, const float* data,
                                                unsigned char r, unsigned char g,
                                                unsigned char b, unsigned char a);
VNOISE_API void turb2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                               unsigned char* out, int w, int h,
                                               float ox, float oy, float freq,
                                               int octaves, float lac, float gain,
                                               const vnoise_op_t* ops, int n, const float* data,
                                               unsigned char r, unsigned char g,
                                               unsigned char b, unsigned char a);


/* Domain transform for absolute-cell sampling. Cell (c, r) is mapped by the
 * affine m (c' = m0 c + m1 r + m2, r' = m3 c + m4 r + m5), then displaced by
 * warp_amp times two fBm samples of a warp field (base warp_base,
 * warp_octaves octaves, lacunarity 2, gain 0.5) at
 * (c' * warp_freq + 5.2, r' * warp_freq + 1.3) and
 * (c' * warp_freq + 1.7, r' * warp_freq + 9.2) when warp_amp != 0, and
 * finally evaluated at (ox + c'' * freq, oy + r'' * freq). */
typedef struct {
    float m[6];
    float ox, oy, freq;
    float warp_amp, warp_freq;
    int warp_octaves;
    int warp_base;
} vnoise_domain_t;

#define VNOISE_MODE_FBM   0
#define VNOISE_MODE_RIDGE 1
#define VNOISE_MODE_TURB  2

/* Fills out[j * w + i] with cell (c0 + i, r0 + j) through the domain d and a
 * fractal sampler of the given mode (VNOISE_MODE_*). A cell's value depends
 * only on its absolute index, so overlapping blocks agree. */
VNOISE_API void vnoise_fill_domain(const noise_state_t* s, int base, int mode,
                                   float* out, int c0, int r0, int w, int h,
                                   const vnoise_domain_t* d,
                                   int octaves, float lac, float gain);

/* Neighborhood kernels, all in "valid" mode: they read a contiguous sw x sh
 * buffer and write a contiguous (sw - 2R) x (sh - 2R) one, where R is the
 * kernel's border radius; output (i, j) corresponds to input (i + R, j + R).
 * They never read outside the input and do nothing for NULL pointers or an
 * empty output. src and dst must not overlap. */

/* Correlation with a row-major (2r + 1)^2 kernel. R = r. */
VNOISE_API void vnoise_convolve(const float* src, int sw, int sh, float* dst,
                                const float* kernel, int r);
/* Horizontal pass with kx, then vertical pass with ky (2r + 1 taps each). R = r. */
VNOISE_API void vnoise_convolve_sep(const float* src, int sw, int sh, float* dst,
                                    const float* kx, const float* ky, int r);

#define VNOISE_SOBEL_MAG 0
#define VNOISE_SOBEL_X   1
#define VNOISE_SOBEL_Y   2
/* Sobel responses divided by 4 (a 0 -> 1 step gives |g| = 1), times k:
 * magnitude, x or y (signed). R = 1. */
VNOISE_API void vnoise_sobel(const float* src, int sw, int sh, float* dst,
                             int mode, float k);

#define VNOISE_MORPH_ERODE    0
#define VNOISE_MORPH_DILATE   1
#define VNOISE_MORPH_OPEN     2
#define VNOISE_MORPH_CLOSE    3
#define VNOISE_MORPH_GRADIENT 4
#define VNOISE_MORPH_TOPHAT   5
#define VNOISE_MORPH_BLACKHAT 6
#define VNOISE_SHAPE_SQUARE 0
#define VNOISE_SHAPE_DISC   1
/* Grayscale morphology (binary on 0/1 buffers): erode = min, dilate = max
 * over a square or disc (dx^2 + dy^2 <= r^2) element; open = dilate(erode),
 * close = erode(dilate), gradient = dilate - erode, tophat = v - open,
 * blackhat = close - v. R = vnoise_morph_radius(op, r). */
VNOISE_API void vnoise_morph(const float* src, int sw, int sh, float* dst,
                             int op, int r, int shape);
/* Border radius of a morphology op: 2r for open, close, tophat and
 * blackhat, r otherwise. */
VNOISE_API int vnoise_morph_radius(int op, int r);

/* Median of the (2r + 1)^2 window. R = r. */
VNOISE_API void vnoise_median(const float* src, int sw, int sh, float* dst, int r);

/* min(d, r) / r, d the Euclidean distance to the nearest cell with v >= t
 * within the disc of radius r (1 when there is none). R = r. */
VNOISE_API void vnoise_distance(const float* src, int sw, int sh, float* dst,
                                int r, float t);

/* Region masks. Shapes use absolute cell coordinates:
 *   RECT     p = x0, y0, x1, y1 (inclusive bounds)
 *   ELLIPSE  p = cx, cy, rx, ry
 *   POLYGON  p0 = offset, p1 = vertex count of x, y pairs in data (even-odd)
 *   RANGE    p = lo, hi on the stage input value
 * The weight is 1 inside and 0 outside; with feather > 0 it is
 * clamp(d / feather, 0, 1), d the distance inside the boundary (cells, or
 * value units for RANGE). invert != 0 takes 1 - weight. */
#define VNOISE_MASK_RECT    0
#define VNOISE_MASK_ELLIPSE 1
#define VNOISE_MASK_POLYGON 2
#define VNOISE_MASK_RANGE   3

typedef struct {
    int type;
    int invert;
    float feather;
    float p[4];
} vnoise_mask_t;

/* dst[j * w + i] = before + m * (dst - before) for the cell
 * (c0 + i, r0 + j), with before = before_buf[j * before_stride + i]. */
VNOISE_API void vnoise_mask_blend(float* dst, int w, int h,
                                  const float* before, int before_stride,
                                  int c0, int r0, const vnoise_mask_t* mask,
                                  const float* data);

#ifdef __cplusplus
}
#endif

#endif