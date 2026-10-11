# matrix-filters Specification

## Purpose
Define whole-matrix filters: stream-power erosion shared with terrain plans, pipeline stages applied to matrices with clamped edges, and resampling between matrix sizes.
## Requirements
### Requirement: Erosion on a matrix
The library SHALL export `vnoise_erode_matrix(float* m, int w, int h, const vnoise_erosion_t* ep, const float* uplift, float* flow_out)`. It SHALL run the terrain plan's stream-power erosion and hillslope diffusion on the matrix itself, with the parameters `iterations`, `reroute`, `k`, `m`, `dt`, `uplift_rate`, `diffusion` (≤ 0.25), `sea_level`, `outlets` (as in `terrain-plan`) and `max_cells`. `uplift` is an optional matrix. Above `max_cells` cells (default 262144, at most 1048576), it SHALL erode a downsample of at most `max_cells` cells and add the bilinearly upsampled height change to the original, so the cost stays bounded. Each priority-flood over 1M cells takes about 100 ms, and erosion repeats it every `reroute` steps. When `flow_out` is given, it SHALL receive `log(1 + A) / log(1 + A_max)`. The terrain plan SHALL share this implementation, and its outputs SHALL be bit-identical to those before this change.

#### Scenario: Valleys form
- **WHEN** a noisy ridge matrix is eroded with 100 iterations
- **THEN** the mean height of the cells with the top 5% of flow, divided by the mean height, decreases

#### Scenario: Large matrix
- **WHEN** a 2048 x 2048 matrix is eroded
- **THEN** it completes, the result keeps the original's small-scale detail where erosion changes little, and the time is reported by the tests

#### Scenario: Plan unchanged
- **WHEN** the terrain tests' reference plan is built after the move
- **THEN** its grids and rivers equal a dump made before it

### Requirement: Stages on a matrix
The Lua binding SHALL provide `vnoise.apply_stages(m, w, h, stages)`. It SHALL run pipeline stages (point ops and kernels, with masks in matrix cells) on an existing matrix. The matrix SHALL be padded by the stages' radius with clamped edges, and the result SHALL be written back, clamped to 0..1.

#### Scenario: Blur keeps the size
- **WHEN** `{ { "gaussian", 2 } }` is applied to a 64 x 64 matrix
- **THEN** the matrix stays 64 x 64, the interior equals the pipeline's Gaussian of the same data, and the edges are defined

### Requirement: Resampling
The library SHALL export `vnoise_resample(const float* src, int sw, int sh, float* dst, int dw, int dh, int mode)`, with `VNOISE_RESAMPLE_BILINEAR` and `VNOISE_RESAMPLE_BICUBIC`. Cell centers SHALL be mapped from `dst` to `src`. The bicubic result SHALL be clamped to its 2 x 2 neighborhood. The Lua wrapper SHALL be `vnoise.resample(src, sw, sh, dw, dh, mode)`, returning a new matrix.

#### Scenario: Identity size
- **WHEN** a matrix is resampled to its own size
- **THEN** it is unchanged (within 1e-6)

#### Scenario: No overshoot
- **WHEN** a step edge is upsampled ×4 with bicubic
- **THEN** no value leaves the range of the input

