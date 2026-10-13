# noise-pipeline Specification

## Purpose
Define pipelines (domain plus ordered point and kernel stages with optional region masks) evaluated per block of absolute cells with an apron, so tiled blocks match a single evaluation, and the helpers that turn global statistics into point ops.

## Requirements

### Requirement: Pipeline compilation
The Lua binding SHALL provide `vnoise.compile_pipeline(spec)` with `spec = { domain = <domain spec>, source = <source spec>, stages = { ... } }` (all optional), each stage `{ name, params..., mask = <mask spec> }` naming a point op or a kernel stage (including `gullies`). It SHALL return a compiled pipeline with the total border radius `radius` (sum of the stage radii) and SHALL raise an error naming an unknown stage, a bad parameter, or a radius above the kernel limits (median 7, others 32). A spec holding both `domain` and `source` SHALL raise an error (a source's leaves carry their own domains). A compiled pipeline passed again SHALL be returned unchanged.

#### Scenario: Radius
- **WHEN** a pipeline has stages `gaussian(1)` (radius 3), `threshold(0.5)` and `open(2)` (radius 4)
- **THEN** its radius is 7

#### Scenario: Gullies radius
- **WHEN** a pipeline has stages `gullies` and `blur(2)`
- **THEN** its radius is 3

#### Scenario: Domain and source together
- **WHEN** a spec has both `domain` and `source`
- **THEN** `compile_pipeline` raises an error naming `source`

### Requirement: Block evaluation with apron
`vnoise.fill_pipeline(state, kind, pipeline, opts)` SHALL return a `float[w * h]` buffer for the cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)` (opts `c0`, `r0` default 0, `w`, `h` default 256, `ox`, `oy`, `freq`, `octaves`, `lac`, `gain`, `base`, `out`, `clamp`). It SHALL fill the block grown by the pipeline's radius on every side: with the pipeline's `source` through `fill_source` when it has one (then `kind` may be nil and the sampler opts are ignored), else by sampling the noise with the pipeline's domain. It SHALL then run the stages in order on unclamped values, passing each kernel stage the absolute cell origin of its input buffer and the state, and clamp the final values to 0..1 unless `clamp = false`. Evaluating a region as any tiling of blocks SHALL give the same values as one call over the region, within 1e-5.

#### Scenario: Tiling equals the whole
- **WHEN** a pipeline with a rotated, warped domain, a Gaussian blur, a threshold, an opening and a masked stage is evaluated over 64 x 64 cells, and again as four 32 x 32 blocks
- **THEN** every cell agrees within 1e-5

#### Scenario: Point-only pipeline equals a chain
- **WHEN** a pipeline holds only point ops and an identity domain
- **THEN** its output equals `fill_grid` with the same ops within 1e-5

#### Scenario: Source pipeline
- **WHEN** a pipeline has `source = { "add", leafA, leafB }` and a Gaussian stage, and is filled with `kind = nil` as one block and as four blocks
- **THEN** both agree within 1e-5, and without stages the output equals `fill_source` of the tree clamped to 0..1

#### Scenario: Legacy specs unchanged
- **WHEN** a pipeline spec without `source` from the existing tests is evaluated
- **THEN** its output is identical to the output before this change

### Requirement: Region masks
A stage's `mask` SHALL be `{ "rect", x0, y0, x1, y1 }` (inclusive absolute cell bounds), `{ "ellipse", cx, cy, rx, ry }`, `{ "polygon", { x1, y1, x2, y2, ... } }` (at least three vertices, even-odd rule) or `{ "range", lo, hi }` (on the stage input), with optional `feather` (default 0) and `invert` (default false). The weight `m` SHALL be 1 inside and 0 outside, faded over `feather` inside the boundary, and `1 - m` when inverted; the stage result SHALL be `before + m * (after - before)`, `before` the stage input at the same cell. The C side SHALL export `vnoise_mask_blend(float* dst, int w, int h, const float* before, int before_stride, int c0, int r0, const vnoise_mask_t* mask)`; a polygon mask SHALL carry its vertex pool in `vnoise_mask_t.data`.

#### Scenario: Rectangle mask
- **WHEN** `invert` runs with mask `{ "rect", 2, 2, 5, 5 }` on a constant 0.2 block
- **THEN** cells inside the rectangle are 0.8 and the others 0.2

#### Scenario: Inverted mask
- **WHEN** the same stage has `invert = true`
- **THEN** cells inside are 0.2 and the others 0.8

#### Scenario: Feather
- **WHEN** the mask is `{ "rect", 0, 0, 20, 20, feather = 4 }`
- **THEN** cell `(2, 10)` blends half way (weight 0.5) and cell `(10, 10)` fully

#### Scenario: Range mask
- **WHEN** `scale(0)` runs with mask `{ "range", 0.4, 0.6 }`
- **THEN** values in 0.4..0.6 become 0 and the others are unchanged

### Requirement: Global statistics as point ops
The binding SHALL provide `vnoise.histogram(buf, count, bins, lo, hi)` (counts of values in `bins` equal bins over `[lo, hi]`, values outside go to the end bins), `vnoise.otsu(hist, lo, hi)` (Otsu's threshold as a value in `[lo, hi]`) and `vnoise.equalize_lut(hist, size)` (a `size`-sample monotonic LUT mapping the histogram's CDF over 0..1, for a `lut` stage).

#### Scenario: Otsu on a bimodal buffer
- **WHEN** a buffer holds half its values near 0.2 and half near 0.8
- **THEN** the threshold lies between them

#### Scenario: Equalization
- **WHEN** the LUT is built from a buffer of values in 0..0.5
- **THEN** it is non-decreasing, starts near 0 and reaches 1 at 0.5
