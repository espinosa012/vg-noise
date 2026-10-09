# vnoise

A fast procedural noise library written in C++17, compiled to a shared
library (`libvnoise.dylib` / `.so` / `.dll`) and consumed from
**LuaJIT FFI** with near-zero binding overhead. Designed for
[LÖVE2D](https://love2d.org) games that need real-time procedural
terrain and textures.

No external dependencies — only a C++17 compiler and `make`.

## Features

### Base noise generators (2D / 3D)

- **Perlin** (improved gradient, fade `6t^5 − 15t^4 + 10t^3`) — 2D / 3D
- **Simplex** (classic skewed-lattice simplex; 2D uses 16 evenly spaced unit
  gradients, deterministic)
  — 2D / 3D
- **White noise** (deterministic integer hash of the cell and the seed) — 2D / 3D

All evaluation functions operate on `float` and return values in
`[-1, 1]` (approximately).

### Fractal samplers

Built on top of any base generator via a `base` selector:

- **fBm** — Fractal Brownian Motion (sum of octaves)
- **Ridge** — `(1 − |n|)²` per octave, useful for mountain ridges
- **Turbulence** — `|n|` per octave, non-negative output

Parameters: `octaves`, `lacunarity` (default `2.0`), `gain`
(default `0.5`), `base` (selects the underlying generator).

### Batch APIs (the key to performance)

Instead of calling the C library once per pixel from Lua (causing
thousands of Lua↔C round-trips), vnoise provides batch functions that
fill an entire buffer in a single call. The compiler can auto-vectorize
the inner loop and the FFI overhead is amortized to zero per pixel.

- `vnoise.fill_grid(state, kind, opts)` — fills a `float[w*h]` buffer
  (2D) or `float[w*h*d]` (3D) with fBm / Ridge / Turbulence output.
- `vnoise.fill_white(state, opts)` — fills a `float[w*h]` buffer with
  seeded white noise over integer cells (`state:white2(ox + i, oy + j)`),
  e.g. per-cell random values for procedural placement.
- `vnoise.fill_imagedata(state, kind, img, opts)` — writes directly to
  the raw RGBA8 pointer of a `love.image.ImageData`, remapping the noise
  range `[lo, hi]` to `[0, 255]` with clamping. Ready to upload to the
  GPU as a texture.

### Value operations

An ordered chain of pointwise operations can post-process noise values
in the same pass as the sampling. Ops run in order on unclamped values;
only the final result is (optionally) clamped to `[0, 1]`.

| Op | Effect on `v` |
|----|---------------|
| `remap(lo, hi)` | `(v - lo) / (hi - lo)` (0 for a zero range) |
| `scale(k)` | `v * k` |
| `offset(d)` | `v + d` |
| `contrast(k, pivot)` | `(v - pivot) * k + pivot` |
| `lut(table)` | `v` clamped to `[0, 1]`, then linear interpolation in a table of samples spread evenly over `[0, 1]` |
| `invert()` | `1 - v` |
| `threshold(t)` | `v >= t ? 1 : 0` (binarization) |
| `smoothstep(e0, e1)` | Hermite step from `e0` to `e1` (a threshold when `e0 == e1`) |
| `gamma(g)` | `max(v, 0) ^ g` |
| `quantize(n)` | `n >= 2` levels: `min(floor(clamp01(v) * n), n - 1) / (n - 1)` |
| `clamp(lo, hi)` | explicit intermediate clamp |

`lut` makes any transfer function (curves, terraces, ...) one generic op:
the caller samples the function into a table and the library interpolates
it. Its error against the sampled function is only in the sample interval
holding a kink, at most `|Δslope| / (4 · (count - 1))`.

C: `vnoise_op_t { int op; float p[4]; }` with `VNOISE_OP_*` ids,
`vnoise_apply_ops(v, ops, n, data, clamp01)`, `vnoise_map_buffer(buf,
count, ops, n, data, clamp01)` and `*_fill_imagedata_ops_rgba8` (op chain
instead of `lo`/`hi`). `data` is a float pool that `VNOISE_OP_LUT` ops
index into (`p[0]` = offset, `p[1]` = sample count; NULL when the chain has
no table). Unknown op ids leave the value unchanged.

Lua:

```lua
local chain = vnoise.compile_ops({ { "contrast", 1.8, 0.5 }, { "offset", -0.1 } })
vnoise.fill_imagedata(state, "fbm", img, { lo = -0.8, hi = 0.8, ops = chain }) -- remap(lo, hi) is prepended
vnoise.fill_grid(state, "fbm", { w = 64, h = 64, ops = { { "remap", -1, 1 }, { "scale", 0.5 } } }) -- clamp defaults to true
vnoise.apply_ops(0.4, chain)                                                    -- one value
vnoise.apply_ops(0.75, { { "lut", { 0, 0.2, 1 } } })                            -- 0.6
```

`compile_ops` accepts names or ids and raises on unknown names. A `lut`
entry is `{ "lut", values }` (Lua array) or `{ "lut", float_ptr, count }`;
its samples are copied into the chain's pool (`chain.data`). Pass the
compiled chain to avoid rebuilding it on every call. `make test` runs
`tests/value_ops.lua` with LuaJIT.

### Image processing (domain, kernels, masks, pipelines)

A block of noise values can be processed as a grayscale image (0..1 by
convention, unclamped between stages) while keeping the property that makes
chunked worlds possible: **a cell's value depends only on its absolute cell
index**, never on the block it was computed in. Evaluating a region in one
call or as any tiling of blocks gives the same values (up to float rounding).

- **Domain transforms** move the sample point instead of resampling pixels,
  so they are exact: rotation, scaling, mirroring and translation about a
  pivot (an affine map in cell space) plus optional fBm domain warping.
  C: `vnoise_domain_t`, `vnoise_fill_domain` (cells by absolute index);
  Lua: `vnoise.compile_domain(spec)`, `vnoise.fill_domain(state, kind, opts)`.
- **Neighborhood kernels** work in *valid* mode: an `sw x sh` input gives
  `(sw - 2R) x (sh - 2R)`, `R` the kernel's border radius, and nothing outside
  the input is read. C: `vnoise_convolve` (full kernel), `vnoise_convolve_sep`,
  `vnoise_sobel` (magnitude / x / y, divided by 4 so a 0 -> 1 step gives 1),
  `vnoise_morph` (erode, dilate, open, close, gradient, top-hat, black-hat;
  square or disc element; binary morphology on 0/1 images) with
  `vnoise_morph_radius`, `vnoise_median`, `vnoise_distance` (bounded distance
  field to cells `>= t`).
- **Masks** restrict a stage to a region: rectangle, ellipse, polygon (absolute
  cell coordinates) or a value range on the stage input, with optional
  `feather` (fade inside the boundary) and `invert`. The stage result is
  `before + m * (after - before)`. C: `vnoise_mask_t`, `vnoise_mask_blend`.
- **Pipelines** tie it together. `fill_pipeline` samples the block grown by the
  pipeline's total radius (the apron), runs the stages shrinking the buffer,
  and clamps the final values unless `clamp = false`. Consecutive unmasked
  point ops run as one fused chain.

```lua
local p = vnoise.compile_pipeline({
  domain = { rotate = 30, scale = 2, pivot = { 128, 128 }, warp = { amp = 8, freq = 0.02, octaves = 3 } },
  stages = {
    { "remap", -1, 1 },
    { "gaussian", 1.5 },                   -- radius ceil(3 sigma) = 5
    { "threshold", 0.55 },
    { "open", 1, shape = "disc" },         -- radius 2
    { "invert", mask = { "ellipse", 128, 128, 60, 40, feather = 10 } },
  },
})
-- Cells (c0 .. c0 + 63, r0 .. r0 + 63); cell (c, r) samples (ox + c' * freq, oy + r' * freq).
local buf = vnoise.fill_pipeline(state, "fbm", p, { c0 = 64, r0 = 0, w = 64, h = 64, freq = 0.01, octaves = 6 })
```

| Stage | Parameters | Radius |
|-------|------------|--------|
| point ops | as in `compile_ops` | 0 |
| `convolve` | `kernel` (flat or nested odd square table, correlation) | `(side - 1) / 2` |
| `blur` | `r` (box) | `r` |
| `gaussian` | `sigma` | `ceil(3 sigma)` |
| `sharpen`, `emboss`, `laplacian` | `k` (default 1) | 1 |
| `sobel`, `sobel_x`, `sobel_y` | `k` (default 1) | 1 |
| `erode`, `dilate`, `morph_gradient` | `r`, `shape` (`"square"`, `"disc"`) | `r` |
| `open`, `close`, `tophat`, `blackhat` | `r`, `shape` | `2r` |
| `median` | `r` (at most 7) | `r` |
| `distance` | `r`, `t` (default 0.5); `min(d, r) / r` | `r` |

Radii are integers up to 32. The apron multiplies the sampled area by
`((w + 2R) / w)^2`; measured on a 64 x 64 block (6 octaves, Apple M-series):
0.28 ms raw, 0.33 ms with Gaussian 1.5 + threshold, 0.36 ms with open 2 (disc)
+ Sobel, 2.4 ms with domain warp + median 2 + distance 8 (warping costs two
extra fBm samples per cell).

Statistics over the whole image (normalization, histogram equalization,
Otsu) are not block independent, so they are resolved once on a probe buffer
of your choice into point ops: `vnoise.histogram(buf, count, bins, lo, hi)`,
`vnoise.otsu(hist, lo, hi)` (value for a `threshold` stage) and
`vnoise.equalize_lut(hist, size)` (samples for a `lut` stage). Operations that
are inherently global (connected components, unbounded distances) are not
provided.

### Determinism

- Same seed produces the **same output within the same build**
  (verified bit-identical across runs).
- Bit-identity across platforms/compilers is **not** guaranteed due to
  `-ffast-math` reordering — acceptable for visual noise, not for
  cross-platform synchronized netcode.

## Build

```sh
make                      # builds libvnoise.dylib / .so / .dll
make NATIVE=0             # portable build (omits -march=native)
make CXX=clang++-15       # use a specific compiler
make clean
```

Platform detection is automatic via `uname -s`:

| Platform | Output              |
|----------|---------------------|
| macOS    | `libvnoise.dylib`  |
| Linux    | `libvnoise.so`      |
| Windows  | `libvnoise.dll`     (MinGW) |

**Default compile flags:**
`-O3 -ffast-math -fno-rtti -fno-exceptions -fPIC -fvisibility=hidden
-march=native -std=c++17`

Use `make NATIVE=0` to distribute builds to CPUs without the host's
specific instruction set extensions.

## Usage from Love2D

1. Place `libvnoise.<ext>` and `lua/vnoise.lua` somewhere LuaJIT can
   find them (your project directory, or anywhere on `package.cpath` /
   `package.path`).
2. In `main.lua`, make the paths reachable:

   ```lua
   package.cpath = package.cpath .. ";./?.dylib;./libvnoise.dylib"
   package.path  = package.path  .. ";./lua/?.lua"
   ```
   (Linux: `.so`; Windows: `.dll`.)

3. Load and use:

   ```lua
   local vnoise = require("vnoise")

   --- Create a seeded state (deterministic).
   local s = vnoise.new(42)

   --- Per-point evaluation.
   local v  = s:perlin2(1.5, 2.5)
   local v3 = s:simplex3(0.1, 0.2, 0.3)
   local w  = s:white2(7, 3)

   --- Fractal samplers with defaults lac=2.0, gain=0.5, octaves=6.
   local h = s:fbm2(1.0, 1.0, 6, vnoise.BASE_SIMPLEX2)
   local r = s:ridge2(1.0, 1.0)
   local t = s:turb2(1.0, 1.0)

   --- Batch fill: a float[w*h] buffer in a single C call.
   local buf = vnoise.fill_grid(s, "fbm", {
       w = 256, h = 256, ox = 0, oy = 0,
       freq = 0.01, octaves = 6, lac = 2.0, gain = 0.5,
       base = vnoise.BASE_SIMPLEX2,
   })

   --- Direct write to a love ImageData (RGBA8, clamped to [lo,hi]).
   local img = love.image.newImageData(256, 256)
   vnoise.fill_imagedata(s, "fbm", img, {
       freq = 0.01, octaves = 6, base = vnoise.BASE_SIMPLEX2,
       lo = -1, hi = 1,
       r = 255, g = 255, b = 255, a = 255,
   })
   local tex = love.graphics.newImage(img)
   ```

## Example

```sh
love examples/love2d
```

Opens a 1024×768 window showing two things side by side:

- **Left**: a 256×256 texture generated by `fill_imagedata` (fBm +
  Simplex, 6 octaves).
- **Right**: an isometric mesh built from the same heightmap via
  `fill_grid` + `love.graphics.newMesh`, slowly rotating.

Same seed → same output every run.

## Base constants

```lua
vnoise.BASE_PERLIN2
vnoise.BASE_PERLIN3
vnoise.BASE_SIMPLEX2
vnoise.BASE_SIMPLEX3
vnoise.BASE_WHITE2
vnoise.BASE_WHITE3
```

Invalid base values silently return `0.0` (no exception thrown).

## Lua API reference

### `vnoise.new(seed) -> state`
Creates a `noise_state_t` via FFI, initializes it with `noise_init`,
returns a Lua wrapper object. Garbage-collected by LuaJIT.

### State methods (per-point)

| Method                                            | Returns         |
|---------------------------------------------------|-----------------|
| `state:perlin2(x, y)`                             | `float ∈ [-1,1]`|
| `state:perlin3(x, y, z)`                          | `float ∈ [-1,1]`|
| `state:simplex2(x, y)`                            | `float ∈ [-1,1]`|
| `state:simplex3(x, y, z)`                         | `float ∈ [-1,1]`|
| `state:white2(ix, iy)`                            | `float ∈ [-1,1]`|
| `state:white3(ix, iy, iz)`                        | `float ∈ [-1,1]`|

### State methods (fractal, per-point)

| Method                              | Defaults                                |
|-------------------------------------|------------------------------------------|
| `state:fbm2(x, y, octaves, base, lac, gain)` | `octaves=6`, `lac=2.0`, `gain=0.5`      |
| `state:fbm3(x, y, z, octaves, base, lac, gain)` | `octaves=6`, `lac=2.0`, `gain=0.5`      |
| `state:ridge2(x, y, octaves, base, lac, gain)` | same                                     |
| `state:ridge3(...)`                  | same                                     |
| `state:turb2(x, y, octaves, base, lac, gain)` | same                                     |
| `state:turb3(...)`                   | same                                     |

### Batch helpers (module-level)

```lua
vnoise.fill_grid(state, kind, opts) -> float* cdata
vnoise.fill_volume(state, kind, opts) -> float* cdata
vnoise.fill_imagedata(state, kind, img, opts) -> img
vnoise.fill_white(state, opts) -> float* cdata   -- w, h, ox, oy (integer cells), out, ops, clamp
```

Where `kind` is one of `"fbm"`, `"ridge"`, `"turb"`.

`opts` fields:
- `w`, `h` (and `d` for volume) — buffer dimensions (default 256 / 64)
- `ox`, `oy` (and `oz`) — origin offset (default 0)
- `freq` — sampling frequency / pixel stride (default 0.01)
- `octaves`, `lac`, `gain` — fractal params (defaults 6, 2.0, 0.5)
- `base` — `vnoise.BASE_*` constant (default `BASE_SIMPLEX2`)

`fill_imagedata` extra fields:
- `lo`, `hi` — value range mapped to `[0, 255]` (default `-1`, `1`)
- `r`, `g`, `b`, `a` — base color, scaled by the mapped factor
  (default `255, 255, 255, 255`)

## C API reference

See `cpp/include/vnoise/vnoise.h`. All public functions are
`extern "C"` and prefixed with the `VNOISE_API` macro (which expands to
`__declspec(dllexport)` on Windows when `VNOISE_LIBRARY` is defined, to
`__attribute__((visibility("default")))` on macOS/Linux, and is empty
when consuming the header from C).

```c
typedef struct {
    unsigned int perm[512];
    unsigned long long seed;
} noise_state_t;

void  noise_init(noise_state_t* s, unsigned long long seed);

float perlin2_eval (const noise_state_t*, float x, float y);
float perlin3_eval (const noise_state_t*, float x, float y, float z);
float simplex2_eval(const noise_state_t*, float x, float y);
float simplex3_eval(const noise_state_t*, float x, float y, float z);
float white2_eval  (const noise_state_t*, int ix, int iy);
float white3_eval  (const noise_state_t*, int ix, int iy, int iz);
void  white2_fill_grid(const noise_state_t*, float* out, int ox, int oy, int w, int h);

float fbm2_eval   (const noise_state_t*, int base, float x, float y,
                   int octaves, float lac, float gain);
float fbm3_eval   (const noise_state_t*, int base, float x, float y, float z,
                   int octaves, float lac, float gain);
float ridge2_eval (const noise_state_t*, int base, float x, float y,
                   int octaves, float lac, float gain);
float ridge3_eval (const noise_state_t*, int base, float x, float y, float z,
                   int octaves, float lac, float gain);
float turb2_eval  (const noise_state_t*, int base, float x, float y,
                   int octaves, float lac, float gain);
float turb3_eval  (const noise_state_t*, int base, float x, float y, float z,
                   int octaves, float lac, float gain);

void fbm2_fill_grid (const noise_state_t*, int base, float* out,
                     float ox, float oy, int w, int h, float freq,
                     int octaves, float lac, float gain);
void ridge2_fill_grid(const noise_state_t*, int base, float* out,
                      float ox, float oy, int w, int h, float freq,
                      int octaves, float lac, float gain);
void turb2_fill_grid (const noise_state_t*, int base, float* out,
                      float ox, float oy, int w, int h, float freq,
                      int octaves, float lac, float gain);

void fbm3_fill_volume  (const noise_state_t*, int base, float* out,
                        float ox, float oy, float oz, int w, int h, int d,
                        float freq, int octaves, float lac, float gain);
void ridge3_fill_volume(const noise_state_t*, int base, float* out,
                        float ox, float oy, float oz, int w, int h, int d,
                        float freq, int octaves, float lac, float gain);
void turb3_fill_volume (const noise_state_t*, int base, float* out,
                        float ox, float oy, float oz, int w, int h, int d,
                        float freq, int octaves, float lac, float gain);

void fbm2_fill_imagedata_rgba8  (const noise_state_t*, int base,
                                 unsigned char* out, int w, int h,
                                 float ox, float oy, float freq,
                                 int octaves, float lac, float gain,
                                 float lo, float hi,
                                 unsigned char r, unsigned char g,
                                 unsigned char b, unsigned char a);
void ridge2_fill_imagedata_rgba8(...);
void turb2_fill_imagedata_rgba8 (...);
```

Inspection: `nm -gU libvnoise.<ext>` shows only the exported
unmangled C symbols of `vnoise.h` — no internal C++ symbols leak across the ABI
boundary (thanks to `-fvisibility=hidden` + `VNOISE_API`).

## Project structure

```
cpp/
  include/vnoise/vnoise.h     Public C API (extern "C", VNOISE_API macro)
  include/vnoise/internal.h   Internal helpers (visibility hidden):
                              splitmix64, xorshift32, fade, lerp,
                              grad2/grad3, simplex2/3, fbm_sample,
                              FractalMode enum, seed_rng
  src/state.cpp               noise_init (Fisher-Yates on perm[])
  src/hash.cpp                seed_rng helper
  src/perlin.cpp              Perlin 2D/3D
  src/simplex.cpp             Simplex 2D/3D
  src/white.cpp               White noise 2D/3D
  src/fbm.cpp                 fBm 2D/3D (octave dispatcher)
  src/fractal.cpp             Ridge 2D/3D + Turbulence 2D/3D
  src/fill_grid.cpp           Batch fill_grid (2D) + fill_volume (3D)
  src/fill_imagedata.cpp      Batch fill_imagedata_rgba8 (2D)
  src/value_ops.cpp           Value-op chains over values and buffers
  src/domain.cpp              Absolute-cell sampling through a domain transform
  src/kernels.cpp             Valid-mode kernels (convolution, Sobel, morphology,
                              median, distance)
  src/mask.cpp                Region masks and mask blending
lua/vnoise.lua                LuaJIT FFI binding + ergonomic wrappers
examples/love2d/conf.lua      Love2D config (1024x768 window)
examples/love2d/main.lua      Demo: texture + isometric mesh
tests/smoke.lua              18 luajit checks (range, determinism,
                              batch==per-point, clamping, invalid base)
tests/determinism.lua        Bit-identity cross-run + clamping
tests/value_ops.lua          Value-op chains (make test)
tests/image_ops.lua          Domain, kernels, masks, pipelines (make test)
Makefile                     Cross-platform build, no CMake
README.md                    This file
```

## Verification

```sh
make clean && make
DYLD_LIBRARY_PATH=. luajit tests/smoke.lua         # macOS
LD_LIBRARY_PATH=.   luajit tests/smoke.lua         # Linux
DYLD_LIBRARY_PATH=. luajit tests/determinism.lua
love examples/love2d
```

Expected: all 18 smoke checks pass, determinism confirms bit-identical
output for the same seed, and the Love2D example opens a window with
the generated terrain.

## Limitations

- **No cross-platform bit-identity** — `-ffast-math` allows the
  compiler to reorder FP operations, so values may differ in the last
  bits between compilers/architectures. Same seed → same result within
  the same build. Sufficient for visual noise, not for cross-platform
  synchronized netcode.
- **No NaN/Inf input support** — undefined behavior under `-ffast-math`.
- **No null pointer validation** — `fill_grid` and `fill_imagedata*`
  do not check `out == NULL` for performance. Caller (LuaJIT FFI) is
  responsible. Calling with `NULL` is undefined behavior.
- **Windows build** — guaranteed with MinGW (`g++`). MSVC is not
  tested but should work if the `VNOISE_API` macro is extended.
- **No 4D / Worley / Voronoi** — out of scope for v1, may be added
  later.
- **No hand-written SIMD intrinsics** — relies on compiler
  auto-vectorization with `-O3 -ffast-math -march=native`, which
  empirically reaches ~80% of optimal. Hand-tuned AVX/NEON can be
  added in a future revision if profiling demands it.

## Performance tips

- **Prefer batch APIs** (`fill_grid`, `fill_imagedata`) over per-point
  calls for large regions. A 1024×1024 heightmap becomes a single C
  call instead of ~1M Lua↔C round-trips.
- **Use `BASE_SIMPLEX2` / `BASE_SIMPLEX3`** for most terrain — better
  visual quality than Perlin at similar cost, and faster than Perlin
  in 3D.
- **Keep `octaves` ≤ 6** unless you really need extra detail; each
  octave doubles the cost.
- **Reuse the same `noise_state_t`** across frames / regions with the
  same seed to amortize `noise_init` (it's already cheap, but no need
  to redo it).
- **Distribute with `make NATIVE=0`** for builds that must run on
  older CPUs without the host's specific extensions. Keep
  `-march=native` (default) for your own development machine.

## License

The implementation is original. Simplex follows the classic
skewed-lattice formulation.