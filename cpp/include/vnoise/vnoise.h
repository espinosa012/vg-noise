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

/* Calling convention rule: every exported function takes at most 8 integer
 * or pointer arguments and at most 8 float arguments, so on arm64 and x86-64
 * SysV every argument travels in a register. LuaJIT's JIT compiler can place
 * stack-passed FFI arguments wrongly on macOS arm64 (a callee then reads a
 * neighbouring stack slot, e.g. a garbage octave count), so functions that
 * need more inputs take them through a struct pointer instead. */

/* Upper bound on every octave count (fractal samplers, warp, cellular,
 * damped, gullies). Larger values are clamped to it: beyond ~24 octaves the
 * added detail is below float precision, and a corrupted count must not turn
 * a fill into a multi-second loop. */
#define VNOISE_MAX_OCTAVES 32

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

/* Image fills: each pixel is t = clamp01((noise - lo) / (hi - lo)) written as
 * (r t, g t, b t, a), with the color packed as
 * rgba = r | g << 8 | b << 16 | a << 24 (see VNOISE_RGBA). */
#define VNOISE_RGBA(r, g, b, a) \
    ((unsigned int)(r) | ((unsigned int)(g) << 8) | ((unsigned int)(b) << 16) | ((unsigned int)(a) << 24))

VNOISE_API void fbm2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                          unsigned char* out, int w, int h,
                                          float ox, float oy, float freq,
                                          int octaves, float lac, float gain,
                                          float lo, float hi, unsigned int rgba);
VNOISE_API void ridge2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                            unsigned char* out, int w, int h,
                                            float ox, float oy, float freq,
                                            int octaves, float lac, float gain,
                                            float lo, float hi, unsigned int rgba);
VNOISE_API void turb2_fill_imagedata_rgba8(const noise_state_t* s, int base,
                                           unsigned char* out, int w, int h,
                                           float ox, float oy, float freq,
                                           int octaves, float lac, float gain,
                                           float lo, float hi, unsigned int rgba);

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

/* A compiled op chain: n ops and the LUT pool they index (NULL without LUT). */
typedef struct {
    const vnoise_op_t* ops;
    int n;
    const float* data;
} vnoise_chain_t;

/* Like *_fill_imagedata_rgba8, but each pixel is t = clamp01(chain(noise))
 * with the op chain in place of the lo/hi range (a NULL chain or ops pointer
 * is the empty chain). */
VNOISE_API void fbm2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                              unsigned char* out, int w, int h,
                                              float ox, float oy, float freq,
                                              int octaves, float lac, float gain,
                                              const vnoise_chain_t* chain, unsigned int rgba);
VNOISE_API void ridge2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                                unsigned char* out, int w, int h,
                                                float ox, float oy, float freq,
                                                int octaves, float lac, float gain,
                                                const vnoise_chain_t* chain, unsigned int rgba);
VNOISE_API void turb2_fill_imagedata_ops_rgba8(const noise_state_t* s, int base,
                                               unsigned char* out, int w, int h,
                                               float ox, float oy, float freq,
                                               int octaves, float lac, float gain,
                                               const vnoise_chain_t* chain, unsigned int rgba);


/* Domain transform for absolute-cell sampling. Cell (c, r) is mapped by the
 * affine m (c' = m0 c + m1 r + m2, r' = m3 c + m4 r + m5), then displaced by
 * warp_amp times two fBm samples of a warp field (base warp_base,
 * warp_octaves octaves, lacunarity warp_lac, gain warp_gain; 0 selects the
 * defaults 2 and 0.5) at (c' * warp_freq + 5.2, r' * warp_freq + 1.3) and
 * (c' * warp_freq + 1.7, r' * warp_freq + 9.2) when warp_amp != 0, and
 * finally evaluated at (ox + c'' * freq, oy + r'' * freq).
 *
 * warp_levels > 1 iterates the warp (Quilez' f(p + a r), r = g(p + a q),
 * q = g(p)): level k samples the warp field at the point displaced by level
 * k - 1, with its own offsets, and the last level's displacement is applied.
 * 0 and 1 are one level (the original warp); at most VNOISE_MAX_WARP_LEVELS. */
#define VNOISE_MAX_WARP_LEVELS 4
typedef struct {
    float m[6];
    float ox, oy, freq;
    float warp_amp, warp_freq;
    int warp_octaves;
    int warp_base;
    int warp_levels;
    float warp_lac, warp_gain;
} vnoise_domain_t;

#define VNOISE_MODE_FBM   0
#define VNOISE_MODE_RIDGE 1
#define VNOISE_MODE_TURB  2

/* Sampler parameters shared by vnoise_fill_domain and vnoise_fill_sampler
 * (modes VNOISE_MODE_*; the cellular and damped modes are defined below). */
/* A grayscale image used as a noise field (see VNOISE_MODE_IMAGE). Opaque;
 * values are floats in 0..1. */
typedef struct vnoise_image_t vnoise_image_t;

typedef struct {
    int mode;
    int base;
    int octaves;
    float lac, gain;
    float jitter;
    float damping;
    float p[4];
    /* VNOISE_MODE_IMAGE only: the image (borrowed, must outlive the fill),
     * a VNOISE_WRAP_* mode and a VNOISE_FILTER_* kind. */
    const vnoise_image_t* image;
    int wrap, filter;
} vnoise_sampler_t;

/* Fills out[j * w + i] with cell (c0 + i, r0 + j) through the domain d and a
 * fractal sampler: sp->mode (VNOISE_MODE_FBM, _RIDGE or _TURB), sp->base,
 * sp->octaves, sp->lac and sp->gain (the other sampler fields are ignored;
 * see vnoise_sampler_t). A cell's value depends only on its
 * absolute index, so overlapping blocks agree. Does nothing for NULL
 * pointers, non-positive sizes or another mode. */
VNOISE_API void vnoise_fill_domain(const noise_state_t* s, const vnoise_sampler_t* sp,
                                   float* out, int c0, int r0, int w, int h,
                                   const vnoise_domain_t* d);

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
    const float* data;  /* POLYGON vertex pool (x, y pairs), NULL otherwise */
} vnoise_mask_t;

/* dst[j * w + i] = before + m * (dst - before) for the cell
 * (c0 + i, r0 + j), with before = before_buf[j * before_stride + i]. */
VNOISE_API void vnoise_mask_blend(float* dst, int w, int h,
                                  const float* before, int before_stride,
                                  int c0, int r0, const vnoise_mask_t* mask);

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
/* IMAGE reads sp->image at the sample point (x, y) in pixel units: integer
 * coordinates are pixel values, so a domain with freq 1 and no transform maps
 * cell (c, r) to pixel (c, r). Octaves, lac and gain are ignored. Outside the
 * image the wrap mode applies; a NULL image fills zeros. */
#define VNOISE_MODE_IMAGE      8

#define VNOISE_WRAP_CLAMP  0
#define VNOISE_WRAP_REPEAT 1
#define VNOISE_WRAP_MIRROR 2

#define VNOISE_FILTER_NEAREST  0
#define VNOISE_FILTER_BILINEAR 1
#define VNOISE_FILTER_BICUBIC  2  /* Catmull-Rom; may overshoot 0..1 slightly */



/* Fills out[j * w + i] with the sampler at the point the domain d maps cell
 * (c0 + i, r0 + j) to (same mapping as vnoise_fill_domain). Does nothing for
 * NULL pointers, non-positive sizes or an unknown mode. */
VNOISE_API void vnoise_fill_sampler(const noise_state_t* s, const vnoise_sampler_t* sp,
                                    float* out, int c0, int r0, int w, int h,
                                    const vnoise_domain_t* d);

/* Image fields. Loads a PNG, JPEG, BMP, TGA or PGM/PNM file as grayscale
 * (colour is converted to luminance; 16-bit files keep their precision) into
 * floats in 0..1, row 0 at the top. Returns NULL on failure, with the reason
 * in vnoise_image_error(). Free with vnoise_image_free. */
VNOISE_API vnoise_image_t* vnoise_image_load(const char* path);

/* Builds an image from raw pixels (row-major, top row first) with `channels`
 * interleaved channels of `bytes` bytes each: 1 (unsigned 8 bit, /255),
 * 2 (unsigned 16 bit native endian, /65535) or 4 (float, kept as is). One and
 * two channels use the first channel; three and four use luminance of the
 * first three (alpha ignored). Returns NULL for bad sizes or formats; the
 * pixels are copied. */
VNOISE_API vnoise_image_t* vnoise_image_from_pixels(const void* data, int w, int h,
                                                    int channels, int bytes);

VNOISE_API void vnoise_image_free(vnoise_image_t* img);
VNOISE_API int vnoise_image_width(const vnoise_image_t* img);
VNOISE_API int vnoise_image_height(const vnoise_image_t* img);
/* The w * h floats (owned by the image); NULL for a NULL image. */
VNOISE_API const float* vnoise_image_data(const vnoise_image_t* img);
/* Reason of the last failed vnoise_image_load (not thread safe). */
VNOISE_API const char* vnoise_image_error(void);

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

/* Destination arrays of vnoise_plan_rivers: per polyline its first vertex,
 * vertex count and mouth (VNOISE_MOUTH_*); per vertex x, y (cells), flow,
 * width, bed. Any NULL array is skipped. */
typedef struct {
    int* start;
    int* count;
    int* mouth;
    float* x;
    float* y;
    float* flow;
    float* width;
    float* bed;
} vnoise_rivers_out_t;

/* Copies the river network into the arrays of out. */
VNOISE_API void vnoise_plan_rivers(const vnoise_plan_t* plan, const vnoise_rivers_out_t* out);

/* Nearest river at cell (c, r) after the meander warp. Returns 1 and writes
 * out[0..4] = distance, bed, width, flow, polyline index; 0 when no segment
 * is indexed in the cell's bucket. */
VNOISE_API int vnoise_plan_query(const vnoise_plan_t* plan, float c, float r, float* out);

/* Output buffers of vnoise_plan_fill (w * h values each); NULL ones are
 * skipped. */
typedef struct {
    float* elevation;
    float* river;
    float* lake;
    float* flow;
    float* channel_distance;
} vnoise_terrain_out_t;

/* Fills the block of cells (c0 .. c0 + w - 1, r0 .. r0 + h - 1). detail is
 * the detail source block (w * h values, clamped to [-1, 1]) or NULL. Every
 * value is in [0, 1] and depends only on the cell. */
VNOISE_API void vnoise_plan_fill(const vnoise_plan_t* plan, int c0, int r0, int w, int h,
                                 const float* detail, const vnoise_terrain_out_t* out);

/* ------------------------------------------------------------------------
 * Matrix operations: positioned edits of a finite row-major float[w * h]
 * matrix. Cell (i, j) has its center at (i + 0.5, j + 0.5); positions and
 * lengths are in cells. Every operation clamps what it writes to 0..1 and
 * depends only on its inputs, parameters and seed. NULL buffers and
 * non-positive sizes do nothing.
 * ------------------------------------------------------------------------ */

#define VNOISE_BLEND_ADD     0  /* m + v */
#define VNOISE_BLEND_SUB     1  /* m - v */
#define VNOISE_BLEND_MAX     2  /* max(m, v) */
#define VNOISE_BLEND_MIN     3  /* min(m, v) (only inside the footprint) */
#define VNOISE_BLEND_REPLACE 4  /* m + w (height - m), w the footprint weight */

#define VNOISE_STAMP_DOME   0  /* (1 - d^2)^2 */
#define VNOISE_STAMP_CONE   1  /* 1 - d, crater inside p[0] (fraction of the radius) */
#define VNOISE_STAMP_CRATER 2  /* rim at 1 - p[0], floor at p[1] (fraction of height) */
#define VNOISE_STAMP_MESA   3  /* flat to 1 - p[0], then a smoothstep to 0 */
#define VNOISE_STAMP_BASIN  4  /* the dome profile applied downward (v = -height * profile) */

/* A point stamp. d is the normalized elliptical distance after rotating by
 * angle (degrees); roughness (0..1) perturbs the outline and the surface with
 * seeded noise. */
typedef struct {
    int shape;
    int blend;
    float cx, cy;
    float rx, ry;
    float angle;
    float height;
    float roughness;
    unsigned long long seed;
    float p[4];
} vnoise_stamp_t;

VNOISE_API void vnoise_stamp(float* m, int w, int h, const vnoise_stamp_t* st);

#define VNOISE_PATH_RIDGE      0  /* mountain range along the line */
#define VNOISE_PATH_VALLEY     1  /* trough (subtracted by default) */
#define VNOISE_PATH_ESCARPMENT 2  /* step raising one side, bounded by reach */

/* A feature along a polyline of n >= 2 points (x, y pairs), smoothed with
 * `smooth` Chaikin passes. width is the full cross width in cells; taper
 * (0..0.5) fades the ends; sharpness shapes the cross profile; peakiness
 * (0..1) mixes in seeded ridged peaks; spurs (cells) warps the distance so
 * flanks branch; side (+1/-1) picks the raised side of an escarpment. */
typedef struct {
    int kind;
    int blend;
    float height;
    float width;
    float taper;
    float sharpness;
    float peakiness;
    float spurs;
    float roughness;
    float reach;
    int side;
    int smooth;
    unsigned long long seed;
} vnoise_path_t;

VNOISE_API void vnoise_path_feature(float* m, int w, int h, const float* points, int n,
                                    const vnoise_path_t* pf);

/* A river traced from (sx, sy) down the steepest descent, breaching pits
 * through their lowest spill point (bounded local flood of breach_radius
 * cells; beyond it the river ends in a lake marked 0.5 in the mask). It stops
 * below sea_level, at the edge, at a cell whose mask is >= 0.75 (a junction)
 * or after max_length cells. The smoothed path's bed (height minus a depth
 * growing along the course) never rises downstream; the channel (width
 * growing from width0) is carved with a valley of `valley` cells and
 * valley_shape, and written to the mask (1 in the channel, fading over
 * `bank`). Writes up to max_points points and returns their count. */
typedef struct {
    float sea_level;
    float width0, width_growth, max_width;
    float depth0, depth_growth, max_depth;
    float valley, valley_shape, bank;
    int breach_radius;
    int smooth;
    int max_length;
} vnoise_river_t;

VNOISE_API int vnoise_river(float* height, int w, int h, float sx, float sy,
                            const vnoise_river_t* rp, float* mask,
                            float* out_points, int max_points);

/* Up to `count` seeded sources on cells >= min_elev (weighted by
 * height - min_elev), at least min_spacing apart; returns how many were found
 * (x, y pairs of cell centers in out_xy). */
VNOISE_API int vnoise_river_sources(const float* height, int w, int h, int count,
                                    float min_elev, float min_spacing,
                                    unsigned long long seed, float* out_xy);

/* Stream-power erosion and hillslope diffusion on the matrix itself (the
 * terrain plan's implementation). Above max_cells (default 262144 when 0, at
 * most 1048576) a downsample is eroded and the upsampled height change added.
 * uplift (optional matrix) scales uplift_rate per cell; flow_out (optional)
 * receives log(1 + A) / log(1 + A_max). */
typedef struct {
    int iterations;
    int reroute;
    float k, m, dt;
    float uplift_rate;
    float diffusion;
    float sea_level;
    int outlets;
    int max_cells;
} vnoise_erosion_t;

VNOISE_API void vnoise_erode_matrix(float* m, int w, int h, const vnoise_erosion_t* ep,
                                    const float* uplift, float* flow_out);

#define VNOISE_RESAMPLE_BILINEAR 0
#define VNOISE_RESAMPLE_BICUBIC  1
/* Scales src (sw x sh) into dst (dw x dh) by cell centers; bicubic is
 * Catmull-Rom clamped to the 2 x 2 neighborhood (no overshoot). */
VNOISE_API void vnoise_resample(const float* src, int sw, int sh, float* dst, int dw, int dh,
                                int mode);

/* ------------------------------------------------------------------------
 * Landform operations on a matrix (same conventions as above): coordinate
 * warping, droplet and thermal erosion, exact distance fields, slope and
 * curvature, flow routing and whole river networks. Heights are converted
 * to cells with `relief`: a value of 1 stands `relief * max(w, h)` cells
 * high, so slopes and talus angles are the same at every matrix resolution.
 * ------------------------------------------------------------------------ */

#define VNOISE_SAMPLE_BILINEAR 0
#define VNOISE_SAMPLE_BICUBIC  1

/* Warp of a matrix: dst(i, j) = src sampled (edge clamped, `filter`) at the
 * cell center displaced by amp * (ux, uy) cells.
 *   vnoise_warp_matrix with dx and dy: u = 2 * (d - 0.5) per axis, so 0.5 is
 *     no displacement;
 *   with dx only (dy NULL): dx is a direction (0..1 = one turn clockwise
 *     from +x on a y-down screen), u its unit vector times strength (optional
 *     matrix, 1 when NULL);
 *   neither: nothing is displaced (dst = src).
 *   vnoise_warp_matrix_noise: (ux, uy) are two fBm samples (base, octaves,
 *     lac, gain) of the warp field of state s at the cell * freq, iterated
 *     `levels` times as in vnoise_domain_t.
 * dst may not alias src. */
typedef struct {
    float amp;
    int filter;
    float freq;
    int octaves;
    float lac, gain;
    int base;
    int levels;
} vnoise_warp_t;

VNOISE_API void vnoise_warp_matrix(const float* src, int w, int h, float* dst,
                                   const float* dx, const float* dy, const float* strength,
                                   const vnoise_warp_t* wp);
/* Noise-driven warp with an explicit state (seeded warp fields). */
VNOISE_API void vnoise_warp_matrix_noise(const float* src, int w, int h, float* dst,
                                         const noise_state_t* s, const vnoise_warp_t* wp);

/* Hydraulic (droplet) erosion: `droplets` seeded droplets, each started on
 * a random cell (rain, if given, accepts it with its value), follow the
 * slope with `inertia`, carry sediment up to capacity = max(-dh, min_slope)
 * * speed * water * capacity, erode (erode rate, spread over a disc of
 * `radius` cells, scaled by 1 - hardness) or deposit (deposit rate), lose
 * `evaporation` of their water each step and live `lifetime` steps; they stop
 * when they enter cells below sea_level (dropping their sediment there) or
 * leave the matrix. change_out (optional) receives 0.5 + 0.5 * dz / max|dz|
 * (above 0.5 deposition, below erosion). */
typedef struct {
    int droplets;
    int lifetime;
    float inertia;
    float capacity, min_slope;
    float erode, deposit;
    float evaporation, gravity;
    int radius;
    float relief;
    float sea_level;
    unsigned long long seed;
} vnoise_hydraulic_t;

VNOISE_API void vnoise_erode_hydraulic(float* m, int w, int h, const vnoise_hydraulic_t* hp,
                                       const float* hardness, const float* rain,
                                       float* change_out);

/* Thermal erosion (talus): `iterations` synchronous passes; where the slope
 * to an 8-neighbor exceeds tan(talus degrees) (heights scaled by relief),
 * `rate` of the steepest excess moves downhill, shared by the steep neighbors
 * in proportion to their excess, scaled by 1 - hardness of the source cell.
 * Material is conserved up to the final clamp. */
typedef struct {
    int iterations;
    float talus;
    float rate;
    float relief;
} vnoise_thermal_t;

VNOISE_API void vnoise_erode_thermal(float* m, int w, int h, const vnoise_thermal_t* tp,
                                     const float* hardness);

#define VNOISE_DIST_OUTSIDE 0  /* cells below threshold: distance to the nearest cell >= threshold */
#define VNOISE_DIST_INSIDE  1  /* cells >= threshold: distance to the nearest cell below it */
#define VNOISE_DIST_SIGNED  2  /* 0.5 on the boundary, rising inside, falling outside */

#define VNOISE_EDGE_NONE  0  /* the matrix edge is not a boundary */
#define VNOISE_EDGE_BELOW 1  /* outside the matrix counts as below the threshold */
#define VNOISE_EDGE_ABOVE 2  /* outside the matrix counts as at or above it */

/* Exact Euclidean distance field (Felzenszwalb-Huttenlocher, separable, in
 * O(w h)) from the set m >= threshold, in cells between centers. With range
 * > 0 the output is min(d, range) / range (signed: 0.5 +- 0.5 * that, with
 * the boundary half a cell from the cells on each side); with range <= 0 it
 * is divided by the largest distance found. Cells with no target at all
 * (empty set) read 1 (outside/inside) or 0 / 1 (signed). */
typedef struct {
    float threshold;
    int mode;
    float range;
    int edge;
} vnoise_distance_t;

VNOISE_API void vnoise_distance_field(const float* m, int w, int h, float* out,
                                      const vnoise_distance_t* dp);

#define VNOISE_SLOPE_ANGLE     0  /* atan(|grad| * relief * max(w, h)) / 90 degrees */
#define VNOISE_SLOPE_GRADIENT  1  /* min(|grad| * relief * max(w, h) / range, 1) */
#define VNOISE_SLOPE_ASPECT    2  /* downhill direction, 0..1 one turn clockwise from +x; flat 0 */
#define VNOISE_SLOPE_DX        3  /* 0.5 + 0.5 * clamp(dz/dx / range): east-facing above 0.5 */
#define VNOISE_SLOPE_DY        4  /* 0.5 + 0.5 * clamp(dz/dy / range) */
#define VNOISE_SLOPE_CURVATURE 5  /* 0.5 + 0.5 * clamp(laplacian * relief * max(w, h) / range):
                                   * above 0.5 concave (valleys), below convex (ridges) */

/* Slope analysis with Horn's 3 x 3 gradient (clamped edges). range is the
 * value mapped to 1 (default 1 when <= 0). */
typedef struct {
    int mode;
    float relief;
    float range;
} vnoise_slope_t;

VNOISE_API void vnoise_slope(const float* m, int w, int h, float* out, const vnoise_slope_t* sp);

#define VNOISE_FLOW_D8  0  /* steepest descent: water follows one neighbor */
#define VNOISE_FLOW_MFD 1  /* multiple flow directions (Freeman): shared by slope^exponent */

#define VNOISE_FLOW_LOG    0  /* log(1 + A) / log(1 + A_max) */
#define VNOISE_FLOW_LINEAR 1  /* A / A_max */
#define VNOISE_FLOW_RANGE  2  /* min(A / range, 1) */

/* Flow routing over the depression-filled matrix (priority-flood; outlets
 * as in the terrain plan). A is the accumulated rain (each cell adds its
 * rain value, 1 without a rain matrix) of the cell and every cell upstream. */
typedef struct {
    int method;
    float exponent;
    int scale;
    float range;
    float sea_level;
    int outlets;
    float lake_depth;
} vnoise_flow_t;

/* Outputs of vnoise_flow; NULL ones are skipped. filled: the depression-
 * filled heights; lake: 1 where filled - height > lake_depth. */
typedef struct {
    float* flow;
    float* filled;
    float* lake;
} vnoise_flow_out_t;

VNOISE_API void vnoise_flow(const float* m, int w, int h, const vnoise_flow_t* fp,
                            const float* rain, const vnoise_flow_out_t* out);

/* Topographic wetness index ln(a / tan(beta)) of the same routing: a is the
 * accumulation A of fp's method (cells of rain draining through the cell, per
 * unit contour width of one cell), tan(beta) the steepest descent to an
 * 8-neighbor on the unfilled heights (scaled by relief * max(w, h) as in
 * vnoise_slope), at least epsilon so pits and flats stay finite. With range > 0
 * the output is clamp(twi / range, 0, 1); with range <= 0 it is stretched
 * from the smallest to the largest index of the matrix. */
typedef struct {
    float relief;
    float epsilon;
    float range;
} vnoise_twi_t;

/* vnoise_flow plus the wetness index into twi (w * h values, optional):
 * the outputs of vnoise_flow are identical. */
VNOISE_API void vnoise_flow_twi(const float* m, int w, int h, const vnoise_flow_t* fp,
                                const vnoise_twi_t* tp, const float* rain,
                                const vnoise_flow_out_t* out, float* twi);

/* A whole river network: D8 drainage of the depression-filled heights, a
 * channel wherever the accumulated rain reaches min_flow, traced from every
 * head to the sea, the edge or a larger river (main stems first, so a
 * tributary joins at the stem's carved bed). Width and depth grow with the
 * flow: width = width0 + width_k * sqrt(A / min_flow - 1) up to max_width,
 * depth likewise. The bed never rises downstream; lake cells (filled more
 * than lake_depth) are crossed at the lake surface and marked 0.5 in the
 * mask, and with fill_lakes the height there is raised to the surface. */
typedef struct {
    float min_flow;
    float sea_level;
    int outlets;
    float width0, width_k, max_width;
    float depth0, depth_k, max_depth;
    float valley, valley_shape, bank;
    float lake_depth;
    int fill_lakes;
    int smooth;
    int min_length;
} vnoise_network_t;

/* Outputs of vnoise_river_network. mask (optional) receives max(mask, 1 in
 * the channel fading over bank, 0.5 in lakes); flow (optional) the
 * log-normalized accumulation. The polylines (downstream order, smoothed)
 * are written into start/count (per river, up to max_rivers) and xy/width
 * (per vertex, up to max_points); rivers that do not fit are carved but not
 * listed. */
typedef struct {
    float* mask;
    float* flow;
    int max_rivers, max_points;
    int* start;
    int* count;
    float* xy;
    float* width;
} vnoise_network_out_t;

/* Returns the number of rivers carved. */
VNOISE_API int vnoise_river_network(float* height, int w, int h, const vnoise_network_t* np,
                                    const float* rain, const vnoise_network_out_t* out);

/* ------------------------------------------------------------------------
 * Climate operations on a matrix (same conventions as the landform
 * operations): blurs at any scale and moisture carried by the wind.
 * ------------------------------------------------------------------------ */

/* Gaussian blur of any width: `passes` (1..8, 3 when <= 0) successive
 * extended box filters (Gwosdek et al. 2011: a box of integer radius r with
 * fractional end weights alpha) per axis, whose variances add up to sigma^2
 * exactly. Each box costs O(1) per value with prefix sums, so a pass costs
 * O(w h + (w + h) sigma) whatever sigma is (the second term is the clamped
 * extension each line carries through the passes). Edges are clamped (the
 * matrix is extended with its border values, as pipeline stages are), so a
 * constant matrix stays constant; sigma (at most 16384) may exceed the
 * matrix size. Not limited by the 32-cell kernel radius of pipelines.
 * sigma <= 0 copies. dst may alias src. */
typedef struct {
    float sigma;
    int passes;
} vnoise_blur_t;

VNOISE_API void vnoise_blur_matrix(const float* src, int w, int h, float* dst,
                                   const vnoise_blur_t* bp);

/* Moisture carried by the wind over a height matrix (orographic
 * precipitation). The wind at each cell is a unit vector: from dir (0..1 =
 * one turn clockwise from +x on a y-down screen, as vnoise_warp_matrix)
 * when given, else from latitude bands by row: bands[0..4] are row
 * fractions (0..1 of the height, non-decreasing) of the polar front, the
 * subtropical ridge, the equator, the other subtropical ridge and the other
 * polar front. Between the ridges blow the trade winds and beyond the polar
 * fronts the polar easterlies (both toward -x), in between the westerlies
 * (toward +x); tilt (degrees) turns easterlies toward the equator and
 * westerlies toward the pole. The bands mirror about the equator, so which
 * edge is north does not matter.
 *
 * The steady state is solved upwind: each cell reads the moisture q at the
 * point one step against the wind, where the wind ray crosses the previous
 * column (or row), interpolated linearly between two cells; the step is
 * L = 1 / max(|ux|, |uy|) cells. Outside the matrix q is `inflow`. On it:
 *   q += evaporation * src * L, capped at capacity, where src is the source
 *     matrix (0..1) or, without one, 1 below sea_level and 0 above;
 *   on land (height >= sea_level) precipitation P = q * clamp(base_rate * L
 *     + orographic * max(0, rise), 0, 1), rise the height gained over the
 *     step in cells (heights below sea_level count as sea_level, scaled by
 *     relief * max(w, h)), and q -= P.
 * Rain shadows follow: the windward slopes wring the air out and the lee
 * gets the dry remainder. `iterations` (1..256, 4 when <= 0) cycles of four
 * Gauss-Seidel sweeps (one per wind quadrant) are run; a uniform wind is
 * exact after one cycle, and winds that turn need more. */
typedef struct {
    float sea_level;
    float evaporation;
    float capacity;
    float base_rate;
    float orographic;
    float relief;
    float inflow;
    float range;
    float fetch_range;
    float bands[5];
    float tilt;
    int iterations;
} vnoise_moisture_t;

/* Outputs of vnoise_moisture (w * h values each); NULL ones are skipped.
 * precip: P / range clamped to 1 (range <= 0: divided by the largest P);
 * moisture: q / capacity; fetch: the distance in cells travelled along the
 * wind since the last cell with src >= 0.5 (0 there; the outside counts as
 * a source when inflow > 0), min(d, fetch_range) / fetch_range (fetch_range
 * <= 0: divided by the largest), 1 where no source lies upwind. */
typedef struct {
    float* precip;
    float* moisture;
    float* fetch;
} vnoise_moisture_out_t;

VNOISE_API void vnoise_moisture(const float* m, int w, int h, const vnoise_moisture_t* mp,
                                const float* src, const float* dir,
                                const vnoise_moisture_out_t* out);

#ifdef __cplusplus
}
#endif

#endif