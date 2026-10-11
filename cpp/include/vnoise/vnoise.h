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

/* ------------------------------------------------------------------------
 * Terrain building blocks
 * ------------------------------------------------------------------------ */

/* 2D Perlin / Simplex noise with analytic gradients: return the same value as
 * perlin2_eval / simplex2_eval and write d/dx, d/dy when dx, dy are not NULL. */
VNOISE_API float perlin2_deriv(const noise_state_t* s, float x, float y, float* dx, float* dy);
VNOISE_API float simplex2_deriv(const noise_state_t* s, float x, float y, float* dx, float* dy);

/* Cellular (Worley) noise: one feature point per integer cell at
 * (i + 0.5 + jitter (u - 0.5), j + 0.5 + jitter (v - 0.5)), u, v hashed from
 * the cell and the seed, jitter clamped to [0, 1]. With d1 <= d2 the distances
 * to the two nearest points, ret selects min(d1, 1), min(d2 / 1.5, 1),
 * min(d2 - d1, 1) or a hash of the nearest point's cell in [0, 1). */
#define VNOISE_CELL_F1    0
#define VNOISE_CELL_F2    1
#define VNOISE_CELL_EDGE  2
#define VNOISE_CELL_VALUE 3
VNOISE_API float cellular2_eval(const noise_state_t* s, float x, float y, float jitter, int ret);

/* Generic sampler. Modes 0..2 are the fractal modes of vnoise_fill_domain;
 * CELL_* average `octaves` octaves of cellular2_eval (weights gain^o, values
 * in [0, 1]); DAMPED is fBm over Perlin/Simplex 2D where each octave adds
 * a n / (1 + damping |D|^2), D the running sum of a * gradient (this octave
 * included), divided by the sum of amplitudes. p[] is reserved. */
#define VNOISE_MODE_CELL_F1    3
#define VNOISE_MODE_CELL_F2    4
#define VNOISE_MODE_CELL_EDGE  5
#define VNOISE_MODE_CELL_VALUE 6
#define VNOISE_MODE_DAMPED     7

typedef struct {
    int mode;
    int base;
    int octaves;
    float lac, gain;
    float jitter;
    float damping;
    float p[4];
} vnoise_sampler_t;

/* Fills out[j * w + i] with the sampler at the point the domain d maps cell
 * (c0 + i, r0 + j) to (same mapping as vnoise_fill_domain). Does nothing for
 * NULL pointers, non-positive sizes or an unknown mode. */
VNOISE_API void vnoise_fill_sampler(const noise_state_t* s, const vnoise_sampler_t* sp,
                                    float* out, int c0, int r0, int w, int h,
                                    const vnoise_domain_t* d);

/* Buffer combinators used by source trees, dst[k] op= src[k] for k < count:
 *   SET dst = w src     ADD dst += w src   MUL dst *= src    MIN, MAX
 *   SUB dst -= src      ABS dst = |dst|    POW dst = max(dst, 0)^w (src unused) */
#define VNOISE_COMBINE_SET 0
#define VNOISE_COMBINE_ADD 1
#define VNOISE_COMBINE_MUL 2
#define VNOISE_COMBINE_MIN 3
#define VNOISE_COMBINE_MAX 4
#define VNOISE_COMBINE_SUB 5
#define VNOISE_COMBINE_ABS 6
#define VNOISE_COMBINE_POW 7
VNOISE_API void vnoise_combine(float* dst, const float* src, int count, int op, float w);
/* dst = dst + t (b - dst). */
VNOISE_API void vnoise_combine_lerp(float* dst, const float* b, const float* t, int count);

/* Gullies erosion filter, a valid-mode kernel of radius 1 (see kernels):
 * src is sw x sh with src[0] at absolute cell (c0, r0). Each output cell
 * takes the central-difference gradient G of the input; with |G| > 0 it adds
 * strength * min(1, sharpness |G| scale) * gully, gully in [-1, 1] the
 * gain-weighted average over `octaves` octaves (spacing scale / 2^i cells) of
 * a smoothly weighted average of cos(2 pi dot(x - q, perp(G) / |G|) /
 * spacing) over the jittered lattice points q near the cell, so the stripes
 * run down the slope. */
VNOISE_API void vnoise_gullies(const float* src, int sw, int sh, float* dst,
                               int c0, int r0, const noise_state_t* s,
                               float scale, float strength, int octaves,
                               float gain, float sharpness);

/* ------------------------------------------------------------------------
 * Terrain plan: a finite world's macro grid with erosion, drainage and a
 * river network, evaluated per block by absolute cell.
 * ------------------------------------------------------------------------ */

#define VNOISE_OUTLETS_EDGES 0
#define VNOISE_OUTLETS_SEA   1
#define VNOISE_OUTLETS_BOTH  2

#define VNOISE_MOUTH_SEA   0
#define VNOISE_MOUTH_EDGE  1
#define VNOISE_MOUTH_RIVER 2

typedef struct {
    int width, height;        /* extent in cells, 1..65536 */
    int macro_cell;           /* macro node spacing in cells, >= 4 */
    float sea_level;          /* 0..1 */
    int outlets;              /* VNOISE_OUTLETS_* */
    unsigned long long seed;  /* seed of the plan's own state (meanders) */

    int erosion_iterations;
    int erosion_reroute;      /* drainage recomputed every this many steps, >= 1 */
    float erosion_k, erosion_m, erosion_dt, erosion_uplift, erosion_diffusion;

    float river_min_flow;     /* in nodes */
    float river_width, river_max_width;   /* cells */
    float river_depth, river_max_depth;   /* value units */
    float lake_depth;
    int river_smooth;         /* Chaikin passes */
    float valley, valley_min, valley_shape, bank;
    float meander_amp, meander_freq;
    float distance_range;

    float detail_amplitude, detail_valley_damping;
} vnoise_plan_params_t;

typedef struct vnoise_plan vnoise_plan_t;

/* Builds a plan from the macro height (and optional uplift, NULL = 0), each
 * mw * mh values with mw = ceil(width / macro_cell) + 1 and likewise mh;
 * node (i, j) lies at cell (i * macro_cell, j * macro_cell). Inputs are
 * clamped to 0..1. Returns NULL on invalid parameters or more than 1048576
 * nodes. */
VNOISE_API vnoise_plan_t* vnoise_plan_create(const vnoise_plan_params_t* params,
                                             const float* height, const float* uplift);
VNOISE_API void vnoise_plan_destroy(vnoise_plan_t* plan);

/* Macro grid size and river network size (polylines, vertices). */
VNOISE_API void vnoise_plan_info(const vnoise_plan_t* plan, int* mw, int* mh,
                                 int* polylines, int* vertices);

#define VNOISE_GRID_HEIGHT   0  /* eroded height */
#define VNOISE_GRID_FILLED   1  /* depression-filled height */
#define VNOISE_GRID_FLOW     2  /* flow accumulation, in nodes */
#define VNOISE_GRID_LAKE     3  /* 1 for lake nodes */
#define VNOISE_GRID_RECEIVER 4  /* receiver node index, -1 for outlets */
#define VNOISE_GRID_OUTLET   5  /* 1 for outlets */
/* Copies a macro grid (mw * mh floats). */
VNOISE_API void vnoise_plan_grid(const vnoise_plan_t* plan, int which, float* out);

/* Copies the river network: per polyline its first vertex, vertex count and
 * mouth (VNOISE_MOUTH_*); per vertex x, y (cells), flow, width, bed. Any
 * NULL array is skipped. */
VNOISE_API void vnoise_plan_rivers(const vnoise_plan_t* plan, int* start, int* count, int* mouth,
                                   float* x, float* y, float* flow, float* width, float* bed);

/* Nearest river at cell (c, r) after the meander warp. Returns 1 and writes
 * out[0..4] = distance, bed, width, flow, polyline index; 0 when no segment
 * is indexed in the cell's bucket. */
VNOISE_API int vnoise_plan_query(const vnoise_plan_t* plan, float c, float r, float* out);

/* Fills the block of cells (c0 .. c0 + w - 1, r0 .. r0 + h - 1). detail is
 * the detail source block (w * h values, clamped to [-1, 1]) or NULL; NULL
 * outputs are skipped. Every value is in [0, 1] and depends only on the cell. */
VNOISE_API void vnoise_plan_fill(const vnoise_plan_t* plan, int c0, int r0, int w, int h,
                                 const float* detail, float* elevation, float* river,
                                 float* lake, float* flow, float* channel_distance);

#ifdef __cplusplus
}
#endif

#endif