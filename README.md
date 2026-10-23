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
count, ops, n, data, clamp01)` and `*_fill_imagedata_ops_rgba8` (a
`vnoise_chain_t { ops, n, data }` instead of `lo`/`hi`). `data` is a float pool that `VNOISE_OP_LUT` ops
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

### Images as noise

A grayscale image is a sampler kind (`"image"`), so it goes through the same
domains, op chains, masks, pipelines and source trees as fBm or cellular noise.
PNG, JPEG, BMP, TGA and PGM files are decoded with stb_image (vendored in
`cpp/third_party/`); colour becomes luminance and 16-bit files keep their
precision, which suits heightmaps. Values are floats in 0..1, row 0 on top.

```lua
local img = vnoise.load_image("height.png")        -- or image_from_pixels(ptr, w, h, 4, 1)
local buf = vnoise.fill_sampler(state, { kind = "image", image = img }, { w = 256, h = 256 })

-- as a leaf of a source tree, mixed with noise and processed like any other
local src = vnoise.compile_source({
  "add",
  { "image", image = "island.png", filter = "bicubic", wrap = "mirror", freq = 0.5 },
  { "fbm", freq = 0.02, octaves = 4 },
  weights = { 0.8, 0.2 },
  ops = { { "smoothstep", 0.2, 0.8 } },
})
```

`freq` defaults to 1 for this kind, so cell `(c, r)` reads pixel `(c, r)` and
`freq = 0.5` stretches the image to twice its size. `filter` is `nearest`,
`bilinear` (default) or `bicubic`; `wrap` is `clamp` (default), `repeat` or
`mirror`. C: `vnoise_image_load`, `vnoise_image_from_pixels`,
`VNOISE_MODE_IMAGE` and the `image`, `wrap`, `filter` fields of
`vnoise_sampler_t`. A LÖVE `ImageData` can be passed with
`vnoise.image_from_pixels(data:getPointer(), w, h, 4, 1)`. Tests:
`tests/image_source.lua`.

### Image processing (domain, kernels, masks, pipelines)

A block of noise values can be processed as a grayscale image (0..1 by
convention, unclamped between stages) while keeping the property that makes
chunked worlds possible: **a cell's value depends only on its absolute cell
index**, never on the block it was computed in. Evaluating a region in one
call or as any tiling of blocks gives the same values (up to float rounding).

- **Domain transforms** move the sample point instead of resampling pixels,
  so they are exact: rotation, scaling, mirroring and translation about a
  pivot (an affine map in cell space) plus optional fBm domain warping.
  C: `vnoise_domain_t`, `vnoise_fill_domain` (cells by absolute index; the
  fractal parameters come in a `vnoise_sampler_t`);
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
  `before + m * (after - before)`. C: `vnoise_mask_t` (a polygon's vertex pool
  in its `data` field), `vnoise_mask_blend`.
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

### Terrain (topography)

Building blocks for plausible elevation maps, keeping the library conventions:
**every elevation and terrain output is in 0..1**, and a cell's value depends
only on its absolute index, so terrain streams in chunks like any pipeline.

**Samplers.** `vnoise.fill_sampler(state, spec, opts)` (C: `vnoise_sampler_t`,
`vnoise_fill_sampler`) is one entry point for every 2D sampler mode, through a
domain like `fill_domain`:

| Kind | Values | Notes |
|------|--------|-------|
| `fbm`, `ridge`, `turb` | as `fill_domain` | bit-identical points |
| `cell_f1`, `cell_f2`, `cell_edge`, `cell_value` | 0..1 | Worley noise: distance to the nearest / second-nearest feature point, their difference (0 on cell borders: ridge and crack networks) and a per-cell value; `jitter` 0..1, fractal sums average octaves |
| `damped` | about -1..1 | fBm in which each octave is damped by `1 / (1 + damping ‖D‖²)`, `D` the running sum of gradients: steep areas lose fine detail (smooth valleys, rough peaks); `damping = 0` is fBm |

`fill_grid`, `fill_domain` and `fill_pipeline` accept every kind above as
their `kind` (the new kinds read `opts.jitter` and `opts.damping`); the
classic kinds keep their dedicated native fills, bit-identical to before.
`simplex2_deriv` and `perlin2_deriv` return the analytic gradient as well;
`cellular2_eval(s, x, y, jitter, ret)` evaluates one cellular octave.

**Source trees.** `vnoise.compile_source(spec)` / `vnoise.fill_source(state,
source, opts)` combine several fields. Leaves are samplers (`{ "ridge", freq =
1/200, octaves = 5, domain = ..., seed = 3, ops = ... }`, `seed` gives the leaf
its own state), `{ "const", v }`, `{ "mask", <mask spec> }` (the weight of a
pipeline mask), `{ "pipeline", <pipeline spec>, kind = ... }` and `{ "plan",
plan, output = name }`; nodes are `add` (with `weights`), `mul`, `min`, `max`,
`sub`, `abs`, `pow` and `lerp`, each with optional `ops`. `stride` samples
every n-th cell (used for macro grids). A pipeline accepts `source = <tree>` in
place of its single sampler (`fill_pipeline(state, nil, p, opts)`), so kernels,
masks and curves run over any combination. `vnoise.presets.continent(opts)`
and `vnoise.presets.mountain_belts(opts)` return ready-made trees in 0..1.

**Gullies.** The pipeline stage `{ "gullies", scale = 8, strength = 0.05,
octaves = 2, gain = 0.5, sharpness = 1 }` (radius 1) is an analytic erosion
filter: on any input it adds stripes aligned with the downhill direction,
stronger on steep slopes, absent on flat ground.

**Terrain plan.** Rivers that run downhill from source to sea depend on the
whole map, so they cannot come from local operations. A plan solves them once
per world on a coarse grid; detail is added per block:

```
 elevation / uplift sources ─► macro grid (a node every macro_cell cells)
   ─► stream-power erosion (implicit, uplift, hillslope diffusion)
   ─► priority-flood ─► D8 receivers ─► flow accumulation ─► lakes
   ─► river polylines (Chaikin-smoothed, width/bed from flow, bed never rises)
   ─► bucket index of the segments
 fill_terrain(block): Catmull-Rom macro height + detail ─► carved valleys
   ─► elevation, river, lake, flow, channel_distance
```

```lua
local s = vnoise.new(7)
local belts = vnoise.presets.mountain_belts({ seed = 2, freq = 1 / 200, belt_freq = 1 / 1500 })
local plan = vnoise.terrain_plan(s, {
  width = 4096, height = 4096, macro_cell = 32, sea_level = 0.3,
  elevation = { "add", vnoise.presets.continent({ width = 4096, height = 4096, seed = 1 }), belts,
                weights = { 0.75, 0.35 }, ops = { { "clamp", 0, 1 } } },
  uplift = belts,
  rivers = { min_flow = 16, meander_amp = 5 },
  detail = { source = { "damped", freq = 1 / 40, octaves = 5, damping = 2 }, amplitude = 0.02 },
})
local out = vnoise.fill_terrain(s, plan, { c0 = 1024, r0 = 512, w = 64, h = 64,
                                          outputs = { "elevation", "river", "lake" } })
for _, r in ipairs(plan:rivers()) do --[[ r.points, r.flow, r.width, r.bed, r.mouth ]] end
local d, bed, width, flow, poly = plan:query(1100, 600) -- nearest river, or nil
```

| Output | Meaning (all 0..1) |
|--------|--------------------|
| `elevation` | macro height (no overshoot) + detail limited by the headroom `min(a, h, 1 - h)` + river valleys carved down to the bed (`valley_shape` < 1 U-shaped, > 1 V-shaped) |
| `river` | 1 in the channel (`d <= width / 2`), fading over `bank` cells |
| `lake` | lake nodes (filled depressions deeper than `lake_depth`) below their surface |
| `flow` | `log(1 + A) / log(1 + A_max)`, the drainage area |
| `channel_distance` | `min(d, distance_range) / distance_range` to the nearest channel |

Options (defaults): `macro_cell` (64), `sea_level` (0), `outlets` (`"both"`,
`"edges"`, `"sea"`); `erosion = { iterations (60), reroute (4), k (0.01), m
(0.5), dt (1), uplift (0.002), diffusion (0.01) }`; `rivers = { min_flow (32
nodes), width (2), max_width (24), depth (0.004), max_depth (0.03), lake_depth
(0.002), smooth (2), valley (6), valley_min (8), valley_shape (1), bank (1),
meander_amp (0), meander_freq (1/64), distance_range (64) }`; `detail = {
source, amplitude (0.05), valley_damping (0.7) }`. `plan:grid(name)` copies a
macro grid (`height`, `filled`, `flow`, `lake`, `receiver`, `outlet`). A plan
output is also a source leaf, so pipelines (e.g. `gullies`) can post-process it.

Cost (Apple M-series, `make`): a 257 x 257 node plan (16384 x 16384 cells at
`macro_cell = 64`) with 100 erosion iterations builds in about 190 ms; a 64 x 64
block with all five outputs and a 6-octave detail source fills in about 0.35
ms. Memory grows with the nodes and river segments, never with the extent.
Rivers exist only inside the plan's finite extent.

### Matrix operations (map authoring)

Terrain plans decide where mountains and rivers go. For authored maps the
library also offers **positioned edits of a finite matrix**: a row-major
`float[w * h]` that each operation reads and modifies in place. Cell `(i, j)`
has its center at `(i + 0.5, j + 0.5)`; positions and lengths are in cells.
Every operation clamps what it writes to 0..1 and is deterministic for equal
inputs, parameters and seed. A consumer (Ludum's Map Editor) keeps a list of
steps and replays them from the first changed one.

```lua
local m = vnoise.fill_grid(state, "fbm", { w = 1024, h = 1024, freq = 1 / 300, ops = { { "remap", -1, 1 } } })
vnoise.stamp(m, 1024, 1024, { shape = "cone", cx = 600, cy = 320, rx = 90, height = 0.4, crater = 0.15, roughness = 0.6 })
vnoise.path_feature(m, 1024, 1024, { 100, 500, 400, 300, 700, 450 }, { kind = "ridge", width = 160, height = 0.35, spurs = 20 })
vnoise.erode(m, 1024, 1024, { iterations = 60, sea_level = 0.3 })
local mask = vnoise.matrix(1024, 1024)
for _, src in ipairs(vnoise.river_sources(m, 1024, 1024, { count = 4, min_elev = 0.6, min_spacing = 150, seed = 7 })) do
  vnoise.river(m, 1024, 1024, src[1], src[2], { sea_level = 0.3 }, mask)
end
vnoise.apply_stages(m, 1024, 1024, { { "gullies", scale = 8, strength = 0.03 } }, state)
local small = vnoise.resample(m, 1024, 1024, 256, 256, "bicubic")
```

| Operation | What it does |
|-----------|--------------|
| `vnoise.stamp(m, w, h, spec)` | point feature: `dome`, `cone` (volcano, `crater` radius), `crater` (`rim`, `floor`), `mesa` (`slope`), `basin`; `cx`, `cy`, `rx`, `ry`, `angle`, `height`, `roughness` (seeded outline and surface noise), `seed` |
| `vnoise.path_feature(m, w, h, points, spec)` | along a polyline (Chaikin-smoothed): `ridge` (mountain range: `width`, `taper`, `sharpness`, `peakiness` ridged peaks, `spurs` branching flanks), `valley`, `escarpment` (raises `side` +1/-1 up to `reach`) |
| `vnoise.river(height, w, h, sx, sy, spec, mask)` | traces down the steepest descent, breaches pits through their spill point (bounded flood of `breach_radius`; beyond it the river ends in a lake, mask 0.5, filled up to the lowest cell on the flood window's border), stops at `sea_level`, the edge or an existing channel (mask ≥ 0.75), carves a channel whose bed never rises (width and depth grow along the course) and writes the mask; returns the points |
| `vnoise.river_sources(height, w, h, spec)` | `count` seeded sources above `min_elev`, weighted by height, `min_spacing` apart |
| `vnoise.erode(m, w, h, spec)` | the plan's stream-power erosion and diffusion on the matrix (optional `uplift` matrix, `flow = true` returns the log-normalized flow); above `max_cells` (default 512²) a downsample is eroded and the height change upsampled |
| `vnoise.apply_stages(m, w, h, stages, state)` | any pipeline stages (point ops, kernels, masks in matrix cells) on the matrix, with clamped-edge padding |
| `vnoise.resample(src, sw, sh, dw, dh, mode)` | `bilinear` or `bicubic` (clamped Catmull-Rom, no overshoot) |

Blends (`blend` in stamps and paths): `add` (default; `sub` for valleys),
`sub`, `max`, `min` (inside the footprint) and `replace` (toward `height`,
weighted by the footprint). C: `vnoise_stamp`, `vnoise_path_feature`,
`vnoise_river`, `vnoise_river_sources`, `vnoise_erode_matrix`,
`vnoise_resample`; the hydrology is shared with terrain plans
(`cpp/src/hydrology.{h,cpp}`).

Cost at 1024² (Apple M-series): a cone stamp about 6 ms, a 4-point ridge
about 32 ms, a river about 1–2 ms, erosion with 60 iterations about 0.5 s
(eroded at 512²).

### Landform operations

Matrix operations that shape and analyze a whole map, with the same
conventions (row-major `float[w * h]`, values in 0..1, deterministic). Those
that need slopes measure heights in cells through `relief`: a value of 1
stands `relief * max(w, h)` cells high (default 0.05), so a slope keeps its
angle when the same map is computed at another resolution.

```lua
local W, H = 1024, 1024
local m = vnoise.fill_source(state, vnoise.presets.continent({ width = W, height = H }), { w = W, h = H })
m = vnoise.warp(m, W, H, { amp = 40, freq = 1 / 120, levels = 2, seed = 5 })  -- organic coasts
vnoise.erode_hydraulic(m, W, H, { sea_level = 0.4, seed = 3 })                 -- gullies, fans, deltas
vnoise.erode_thermal(m, W, H, { talus = 30 })                                  -- cliffs into screes
local coast = vnoise.distance_field(m, W, H, { threshold = 0.4, mode = "signed", range = 64 })
local slope = vnoise.slope(m, W, H, { mode = "angle" })
local wet = vnoise.flow(m, W, H, { method = "mfd", sea_level = 0.4 })
local rivers, mask = vnoise.river_network(m, W, H, { sea_level = 0.4 })         -- every river to the sea
```

| Operation | What it does |
|-----------|--------------|
| `vnoise.warp(m, w, h, spec)` | new matrix sampling `m` at displaced points: by `dx`/`dy` matrices (0.5 = none, 0/1 = -/+`amp` cells), by a `direction` matrix (0..1 = one turn clockwise from +x) with optional `strength`, or by a seeded fBm field (`freq`, `octaves`, `lac`, `gain`, `base`) iterated `levels` (1..4) times; `filter` bilinear or bicubic (no overshoot) |
| `vnoise.erode_hydraulic(m, w, h, spec)` | droplet erosion: `density` droplets per cell (0.3) with `lifetime`, `inertia`, `capacity`, `min_slope`, `erode`, `deposit`, `evaporation`, `gravity`, brush `radius`; they stop at `sea_level` and drop their load (deltas); optional `hardness` and `rain` matrices; `change = true` returns 0.5 + signed change |
| `vnoise.erode_thermal(m, w, h, spec)` | talus erosion: slopes above `talus` degrees shed `rate` of their excess to their foot, for `iterations` synchronous passes; optional `hardness` |
| `vnoise.distance_field(m, w, h, spec)` | exact Euclidean distance (Felzenszwalb-Huttenlocher, unbounded) to the set `m >= threshold`: `outside`, `inside` or `signed` (0.5 on the boundary), `min(d, range) / range` or normalized by the largest; `edge` `below`/`above` counts the outside of the matrix as sea or land |
| `vnoise.slope(m, w, h, spec)` | Horn gradient as `angle` (0 flat .. 1 vertical), `gradient`, `aspect` (downhill direction), `dx`, `dy` or `curvature` (above 0.5 concave) |
| `vnoise.flow(m, w, h, spec)` | accumulated `rain` (default 1 per cell) over the depression-filled heights, `d8` or `mfd` (slope^`exponent`), scaled `log`, `linear` or by `range`; optionally the filled heights, the lake mask and (`twi = true`) the topographic wetness index (see [Climate operations](#climate-operations)) |
| `vnoise.river_network(height, w, h, spec, mask)` | every river whose flow reaches `min_flow` cells of rain, main stems first, tributaries joined at the stem's bed, width/depth growing with `sqrt(flow)`, lakes crossed at their surface (`fill_lakes`), carved in one pass; returns `{ points, width }` per river, the mask and (with `flow = true`) the flow |

The domain warp of sampler fills gains the same iterated levels and
configurable lacunarity and gain: `domain = { warp = { amp, freq, octaves,
levels = 2, lac = 2, gain = 0.5 } }` (one level is the original warp, bit for
bit). C: `vnoise_warp_matrix`, `vnoise_warp_matrix_noise`,
`vnoise_erode_hydraulic`, `vnoise_erode_thermal`, `vnoise_distance_field`,
`vnoise_slope`, `vnoise_flow`, `vnoise_river_network` and their parameter
structs in `vnoise.h`. Tests: `tests/landforms.lua`.

Cost at 1024² (Apple M-series): warp with two levels about 150 ms, hydraulic
erosion about 0.3 s, thermal erosion (50 passes) about 0.5 s, signed distance
about 27 ms, slope 5 ms, flow 0.1 s (D8) / 0.2 s (MFD), river network about
0.12 s.

### Climate operations

Matrix operations for climate maps (precipitation, humidity, smoothed
temperature), with the same conventions as the landform operations.

```lua
local W, H = 1024, 512
local rain, moist, fetch = vnoise.moisture(m, W, H, {
  sea_level = 0.4, moisture = true, fetch = true, fetch_range = 300,
  bands = { 1 / 6, 1 / 3, 0.5, 2 / 3, 5 / 6 }, tilt = 15,            -- winds by latitude
})
rain = vnoise.blur_large(rain, W, H, { sigma = 6 })                   -- soften the rain bands
local _, _, _, twi = vnoise.flow(m, W, H, { method = "mfd", sea_level = 0.4, twi = true })
local sea = vnoise.distance_field(m, W, H, { threshold = 0.4, range = 1 })  -- 1 at sea, 0 on land
local maritime = vnoise.blur_large(sea, W, H, { sigma = 200 })              -- any sigma, same cost
```

| Operation | What it does |
|-----------|--------------|
| `vnoise.moisture(m, w, h, spec)` | moisture carried by the wind with orographic precipitation: the air gains `evaporation` per cell over the sources (`source` matrix, or the cells below `sea_level`) up to `capacity`; over land it rains `base_rate` of its moisture per cell plus `orographic` times the height climbed in cells (`relief`), so windward slopes are wet and their lee is a rain shadow. The wind comes from a `direction` matrix (0..1 = one turn clockwise from +x) or from latitude `bands` by row (polar easterlies, westerlies, trade winds; `tilt` degrees toward the equator or the pole). Returns the precipitation (`/ range`, or `/` the largest), and with `moisture = true` / `fetch = true` the moisture carried and the fetch (distance along the wind since the last source, `/ fetch_range`; 1 where no source lies upwind) |
| `vnoise.blur_large(m, w, h, spec)` | Gaussian blur of any `sigma` (up to 16384 cells, not limited by the 32-cell kernel radius of pipelines): `passes` (3) extended box filters per axis with the exact variance, O(1) per cell, clamped edges like `apply_stages`; within about 1% of the value range of the exact Gaussian |
| `vnoise.flow(..., { twi = true })` | topographic wetness index `ln(A / tan(beta))`: A the flow accumulation (cells of rain, either method), tan(beta) the steepest descent to a neighbor on the unfilled heights (`relief`, at least `epsilon`), `/ twi_range` or stretched to 0..1 when `twi_range` is 0; high on valley floors and flats, low on crests and steep slopes |

**Moisture model.** The steady state is solved upwind: each cell reads the
moisture where the wind ray crosses the previous column (or row), between
two cells, a step of `L = 1 / max(|ux|, |uy|)` cells; air entering from
outside the matrix carries `inflow` (0). Without a `source` matrix the
sources are the cells below `sea_level`, so with the default `sea_level` of
0 only `inflow` brings moisture. Gauss-Seidel sweeps, one per wind
quadrant with rows and columns running with the wind, settle a uniform wind
in one cycle; `iterations` (4) cycles cover winds that turn. The latitude
bands are five row fractions (0..1 of the height, non-decreasing): polar
front, subtropical ridge, equator, subtropical ridge, polar front. Between
the ridges blow the trade winds and beyond the fronts the polar easterlies
(toward -x), in between the westerlies (toward +x); the pattern mirrors about
the equator, so which edge is north does not matter. Precipitation per cell
depends on the step length, so `range` and the rates are per cell of the
matrix being computed (scale them when the same map is computed at another
resolution). Defaults: `evaporation` 0.05, `capacity` 1, `base_rate` 0.002,
`orographic` 1, `relief` 0.05.

C: `vnoise_moisture`, `vnoise_blur_matrix` and `vnoise_flow_twi` (the
outputs of `vnoise_flow` plus the index) with `vnoise_moisture_t`,
`vnoise_moisture_out_t`, `vnoise_blur_t` and `vnoise_twi_t` in `vnoise.h`.
Tests: `tests/climate.lua`.

Cost at 1024² (Apple M-series): moisture with all outputs about 35 ms (4
cycles), large blur about 16 ms at sigma 4 and about 50 ms at sigma 512, flow
with the wetness index about 0.2 s (MFD).

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
love examples/terrain     # terrain plan preview: R new seed, 1-3 views, E erosion, M meanders
love examples/matrix      # matrix authoring: 1-7 show each step, R new seed
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

**Calling convention.** No exported function takes more than 8 integer or
pointer arguments or more than 8 float arguments, so on arm64 and x86-64 SysV
every argument travels in a register. LuaJIT's JIT compiler can place
stack-passed FFI arguments in the wrong slot on macOS arm64: the callee then
reads a neighbouring slot, e.g. a garbage octave count, and a fill that takes
milliseconds can take minutes. Functions with more inputs take them through a
struct pointer (`vnoise_sampler_t`, `vnoise_chain_t`, `vnoise_rivers_out_t`,
`vnoise_terrain_out_t`) or packed (`VNOISE_RGBA`). As a second safeguard,
every octave count is clamped to `VNOISE_MAX_OCTAVES` (32). `tests/abi.lua`
checks the binding's declarations and compares JIT-compiled calls with the
interpreter.

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
                                 unsigned int rgba);  /* VNOISE_RGBA(r, g, b, a) */
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
  src/cellular.cpp            Cellular (Worley) noise
  src/sampler.cpp             Generic sampler entry point, damped fBm
  src/sources.cpp             Buffer combinators for source trees
  src/gullies.cpp             Gullies erosion filter stage
  src/terrain_plan.h          Private terrain plan layout
  src/terrain_plan.cpp        Plan build: erosion, drainage, rivers, index
  src/terrain_fill.cpp        Per-block multi-output plan evaluation
  src/hydrology.{h,cpp}       Shared flood, routing, accumulation, erosion, Chaikin
  src/polyline.h              Nearest-segment queries with a bucket index
  src/matrix_features.cpp     Stamps and path features on matrices
  src/matrix_rivers.cpp       Rivers and random sources on matrices
  src/matrix_filters.cpp      Matrix erosion, resampling and large Gaussian blurs
  src/matrix_analysis.cpp     Matrix warp, distance fields, slope
  src/matrix_erosion.cpp      Hydraulic (droplet) and thermal erosion
  src/matrix_network.cpp      Flow accumulation, wetness index and river networks
  src/matrix_climate.cpp      Moisture transport and orographic precipitation
lua/vnoise.lua                LuaJIT FFI binding + ergonomic wrappers
examples/love2d/conf.lua      Love2D config (1024x768 window)
examples/love2d/main.lua      Demo: texture + isometric mesh
examples/terrain/main.lua     Demo: terrain plan preview (erosion, rivers, lakes)
examples/matrix/main.lua      Demo: step-by-step matrix authoring
tests/smoke.lua              18 luajit checks (range, determinism,
                              batch==per-point, clamping, invalid base)
tests/determinism.lua        Bit-identity cross-run + clamping
tests/value_ops.lua          Value-op chains (make test)
tests/image_ops.lua          Domain, kernels, masks, pipelines (make test)
tests/terrain.lua            Samplers, sources, gullies, terrain plans (make test)
tests/matrix_ops.lua         Stamps, path features, rivers, matrix filters (make test)
tests/landforms.lua          Warp, erosion, distance, slope, flow, river networks (make test)
tests/climate.lua            Moisture, large blur, wetness index (make test)
tests/abi.lua                Register-only signatures, octave bound, JIT vs interpreter (make test)
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