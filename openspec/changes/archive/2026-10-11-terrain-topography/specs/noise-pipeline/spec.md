## MODIFIED Requirements

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
