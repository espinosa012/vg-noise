## Context

vg-noise samples fractal noise into float buffers and applies pointwise value-op chains (`vnoise_op_t`, `vnoise_map_buffer`). Its main consumer streams maps in chunks: each chunk asks for the values of a rectangular block of noise cells and never builds a whole-map buffer. Any new operation must therefore give each cell a value that depends only on the cell's absolute index and the pipeline, never on the block it was computed in.

## Goals / Non-Goals

**Goals:**
- Image-processing operations on noise blocks treated as grayscale images (0..1 by convention, unclamped between stages).
- Block independence: evaluating a region in one call or as any tiling of blocks gives the same values (up to float rounding).
- One implementation for the game's preview and its chunks, native for the per-pixel work.

**Non-Goals:**
- Truly global operations (connected components, unbounded distances): not block independent.
- Multi-input graphs, 3D volumes, image (RGBA) variants of the pipeline.

## Decisions

### Four kinds of operation
- **Point** ops (`v -> f(v)`) extend the existing chain: new ids `INVERT` 5 (`1 - v`), `THRESHOLD` 6 (`v >= p0 ? 1 : 0`), `SMOOTHSTEP` 7 (Hermite step between `p0` and `p1`; a zero-width step is a threshold at `p0`), `GAMMA` 8 (`max(v, 0) ^ p0`), `QUANTIZE` 9 (`floor(clamp01(v) * n) / (n - 1)` with `n = p0 >= 2` levels, 1 maps to the top level), `CLAMP` 10 (`min(max(v, p0), p1)`, an explicit intermediate clamp). They work everywhere a chain is accepted.
- **Domain** transforms move the sample point, not the pixels, so rotation and scaling are exact and leave no empty corners. Implemented in `vnoise_fill_domain`.
- **Neighborhood** kernels read a `(2r + 1)^2` window. They run in *valid* mode: an `sw x sh` input gives a `(sw - 2r) x (sh - 2r)` output and never reads outside the input, so there is no border policy. The pipeline supplies the border by sampling an apron.
- **Global** operations (normalization, histogram equalization, Otsu) are resolved once on a probe buffer by Lua helpers into point ops (`remap`, `lut`, `threshold`). The chosen probe is the caller's decision; after that they are pointwise and block independent.

### Absolute cell sampling
`vnoise_fill_domain(s, base, mode, out, c0, r0, w, h, domain, octaves, lac, gain)` fills cells `(c0 + i, r0 + j)` by absolute integer index. Cell `(c, r)` is first mapped in cell space by the affine `m[6]` (`c' = m0 c + m1 r + m2`, `r' = m3 c + m4 r + m5`), then optionally warped (`c'' = c' + amp * fbm(c' * wf + (5.2, 1.3))`, `r'' = r' + amp * fbm(r'... + (1.7, 9.2))`, both fBm on the same state with `warp_octaves`, lacunarity 2, gain 0.5), then evaluated at `(ox + c'' * freq, oy + r'' * freq)`. With the identity affine and no warp it matches `*_fill_grid` with origin `ox + c0 * freq`. Because each cell's arithmetic uses only `(c, r)`, overlapping blocks agree. `mode` (0 fBm, 1 ridge, 2 turbulence) replaces three entry points.

The Lua binding builds `m` from `rotate` (degrees, the image turns clockwise on a y-down screen for positive angles), `scale` (number or `{sx, sy}`, > 1 magnifies), `flip_x`/`flip_y`, `translate` (cells) and `pivot` (cells, default `{0, 0}`), as the inverse map `c' = pivot + M (c - translate - pivot)` with `M = F * diag(1/sx, 1/sy) * R(-angle)`, mirrors applied last in image terms.

### Kernels in C, orchestration in Lua
Kernels are stateless C functions over contiguous float buffers (`vnoise_convolve`, `vnoise_convolve_sep`, `vnoise_sobel`, `vnoise_morph`, `vnoise_median`, `vnoise_distance`). Presets (box, Gaussian, sharpen, emboss, Laplacian) are kernels built in Lua. The pipeline orchestration (apron, ping-pong buffers, grouping consecutive unmasked point ops into one `vnoise_map_buffer` pass) is in Lua: it runs once per block, its cost is a few FFI calls, and keeping it in the binding avoids a variable-layout stage struct in the C ABI. Kernels allocate their temporaries with `malloc` (morphology composites, separable passes).

Alternatives: a C pipeline interpreter (rejected for now: needs a serialized stage format in the ABI, little gain); same-size kernels with border modes (rejected: border handling would make blocks disagree at their edges).

### Morphology
Grayscale erosion/dilation are min/max filters; on 0/1 images they are binary morphology. Square elements are separable (two 1D passes); discs (`dx^2 + dy^2 <= r^2`) are direct. Composites: open = dilate(erode), close = erode(dilate), gradient = dilate - erode, top-hat = v - open(v), black-hat = close(v) - v. Open, close, top-hat and black-hat consume `2r` of border; erode, dilate and gradient `r`. `vnoise_morph_radius(op, r)` reports it.

### Sobel and distance
Sobel uses the standard 3x3 kernels divided by 4, so a 0 -> 1 step edge gives `|gx| = 1`; `MAG` returns `k * sqrt(gx^2 + gy^2)`, `X`/`Y` return `k * gx` / `k * gy` (signed). A fixed scale (not the block maximum) keeps it block independent. `vnoise_distance(src, ..., r, t)` returns for each cell `min(d, r) / r`, `d` the Euclidean distance to the nearest cell with `v >= t` within radius `r` (0 on such cells, 1 when none is within `r`); offsets are pre-sorted by distance so the search stops at the first hit.

### Masks
`vnoise_mask_t { int type; int invert; float feather; float p[4]; }` with types `RECT` (`x0, y0, x1, y1`, inclusive cell bounds), `ELLIPSE` (`cx, cy, rx, ry`), `POLYGON` (`p0` offset, `p1` vertex count in a float pool of `x, y` pairs; even-odd rule), `RANGE` (`lo, hi` on the stage input). A shape's weight is 1 inside and 0 outside; with `feather > 0` it is `clamp(d / feather, 0, 1)` where `d` is the distance inside the boundary (cells for shapes, value units for `RANGE`), so the fade lies inside the region. `invert` takes `1 - m`. `vnoise_mask_blend(dst, w, h, before, stride, c0, r0, mask, data)` sets `dst = before + m * (dst - before)`; `before` is the stage input aligned with `dst` (offset by the kernel radius, hence its own stride). Shape coordinates are absolute cell indices, so masks are block independent.

### Pipeline API (Lua)
```lua
local p = vnoise.compile_pipeline({
  domain = { rotate = 30, scale = 2, pivot = { 128, 128 }, warp = { amp = 8, freq = 0.02, octaves = 3 } },
  stages = {
    { "remap", -1, 1 },
    { "gaussian", 1.5 },
    { "threshold", 0.55 },
    { "open", 1, shape = "disc" },
    { "invert", mask = { "ellipse", 128, 128, 60, 40, feather = 10 } },
  },
})
local buf = vnoise.fill_pipeline(state, "fbm", p, { c0 = 0, r0 = 0, w = 64, h = 64, freq = 0.01, octaves = 6 })
```
`fill_pipeline` samples `(w + 2R) x (h + 2R)` cells from `(c0 - R, r0 - R)` with `R = p.radius` (sum of stage radii), runs each stage shrinking the buffer by twice its radius, and clamps the final values to 0..1 unless `clamp = false`. Point-op lists and compiled chains stay valid as stage lists.

## Risks / Trade-offs

- [Apron cost] A total radius `R` multiplies the sampled area by `((w + 2R) / w)^2` (64 x 64 block, `R = 8`: 1.56x). Documented; kernels with large radii belong at low resolution.
- [`-ffast-math` and vectorization] Overlapping blocks may differ in the last ulp; tests compare tiled and whole results with a tolerance (1e-5).
- [Median and disc morphology are O(r^2) per cell] Radii are limited (median r <= 7, other kernels r <= 32); the binding raises above them.
- [Global helpers depend on the probe] Equalization or Otsu over different probes give different results; the caller fixes the probe (the game already does this for its AUTO levels).
