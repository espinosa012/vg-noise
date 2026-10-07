## MODIFIED Requirements

### Requirement: Value operation set
The library SHALL define a value operation as `vnoise_op_t { int op; float p[4]; }` and SHALL implement these ops, applied to a value `v`:
- `VNOISE_OP_REMAP` (0): `(v - p[0]) / (p[1] - p[0])`; when `p[1] == p[0]` the result is `0`.
- `VNOISE_OP_SCALE` (1): `v * p[0]`.
- `VNOISE_OP_OFFSET` (2): `v + p[0]`.
- `VNOISE_OP_CONTRAST` (3): `(v - p[1]) * p[0] + p[1]` (factor `p[0]` around pivot `p[1]`).
- `VNOISE_OP_LUT` (4): a look-up table of `count = p[1]` samples starting at `data[p[0]]` in the chain's float pool, spread evenly over `[0, 1]`. `v` is clamped to `[0, 1]` (NaN to 0) and interpolated linearly between the two neighboring samples; a single-sample table is constant. The op leaves the value unchanged when `data` is NULL or `count < 1`.
An unknown op id SHALL leave the value unchanged. Unused `p` entries SHALL be ignored.

#### Scenario: Scale
- **WHEN** `scale(2)` is applied to `0.3`
- **THEN** the result is `0.6`

#### Scenario: Offset
- **WHEN** `offset(-0.25)` is applied to `0.3`
- **THEN** the result is `0.05`

#### Scenario: Contrast around the pivot
- **WHEN** `contrast(2, 0.5)` is applied to `0.75` and to `0.5`
- **THEN** the results are `1.0` and `0.5`

#### Scenario: Remap
- **WHEN** `remap(-1, 1)` is applied to `0`
- **THEN** the result is `0.5`

#### Scenario: Unknown op
- **WHEN** an op with id `999` is applied to `0.3`
- **THEN** the result is `0.3`

#### Scenario: Look-up table
- **WHEN** `lut([0, 0.2, 1])` is applied to `0.75`, `-0.4` and `1.6`
- **THEN** the results are `0.6`, `0` and `1`

### Requirement: Single value and buffer application
The library SHALL export `float vnoise_apply_ops(float v, const vnoise_op_t* ops, int n, const float* data, int clamp01)` and `void vnoise_map_buffer(float* buf, int count, const vnoise_op_t* ops, int n, const float* data, int clamp01)`, where `data` is the float pool for LUT ops (may be NULL); the latter SHALL replace every element of `buf` with the chain applied to it. Both SHALL tolerate `ops == NULL` with `n == 0`, and `vnoise_map_buffer` SHALL do nothing for a NULL buffer or `count <= 0`.

#### Scenario: Buffer equals per-value application
- **WHEN** a filled grid is mapped with a chain
- **THEN** every element equals `vnoise_apply_ops` of the original element with the same chain and clamp flag

### Requirement: Fused image fill with ops
The library SHALL export `fbm2_fill_imagedata_ops_rgba8`, `ridge2_fill_imagedata_ops_rgba8` and `turb2_fill_imagedata_ops_rgba8`, taking the same arguments as the existing image fills but an op chain (`ops`, `n`, `data`) instead of `lo`/`hi`. Each pixel SHALL be `t = clamp01(chain(noise))` written as `(r·t, g·t, b·t, a)`, exactly as the existing fills write `t`.

#### Scenario: Equivalent to lo/hi fill
- **WHEN** an image is filled with the ops variant and the chain `[remap(lo, hi)]`, and another with the existing fill and `lo`, `hi`
- **THEN** both images are identical

### Requirement: Lua binding for ops
The Lua binding SHALL expose `vnoise.OP_REMAP`, `OP_SCALE`, `OP_OFFSET`, `OP_CONTRAST`, `OP_LUT`, and SHALL accept op lists written as `{ name_or_id, p0, p1, ... }` with names `"remap"`, `"scale"`, `"offset"`, `"contrast"`, `"lut"`; a LUT entry is `{ "lut", values }` (Lua array of samples) or `{ "lut", float_ptr, count }`, and a LUT without samples SHALL raise an error. It SHALL provide:
- `vnoise.compile_ops(list)` returning a compiled chain (cdata array plus count, and a float pool `data` with `data_n` samples holding every LUT's samples in order) reusable across calls; an unknown name SHALL raise an error.
- `vnoise.apply_ops(v, ops, clamp)` for one value (`clamp` defaults to true).
- `opts.ops` (list or compiled chain) and `opts.clamp` (default true) on `vnoise.fill_grid`: when `opts.ops` is present the filled grid is mapped through the chain.
- `opts.ops` on `vnoise.fill_imagedata`: when present, the chain used is `remap(opts.lo, opts.hi)` followed by `opts.ops`; when absent the existing fill is called unchanged.

#### Scenario: Grid without ops is raw
- **WHEN** `fill_grid` is called without `opts.ops`
- **THEN** the output is the raw noise, as before

#### Scenario: Grid with ops
- **WHEN** `fill_grid` is called with `ops = { {"remap", -1, 1}, {"scale", 0.5} }`
- **THEN** every element equals `clamp01(((raw + 1) / 2) * 0.5)`

#### Scenario: Image with empty ops
- **WHEN** `fill_imagedata` is called with `ops = {}` and the same `lo`, `hi` as a call without `ops`
- **THEN** both images are identical

#### Scenario: Unknown op name
- **WHEN** `compile_ops({ {"blur", 1} })` is called
- **THEN** an error naming `blur` is raised

#### Scenario: Several tables in one chain
- **WHEN** `compile_ops({ {"lut", {1, 0}}, {"lut", {0, 0.5, 0.5, 1}} })` is applied to `0.25`
- **THEN** the pool holds 6 samples and the result is `0.625`
