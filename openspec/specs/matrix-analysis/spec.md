# matrix-analysis Specification

## Purpose
Define whole-matrix analyses: exact Euclidean distance fields (outside, inside, signed), slope, aspect and curvature with heights in cells, flow accumulation over the depression-filled matrix, and the topographic wetness index.

## Requirements

### Requirement: Distance fields
The library SHALL export `vnoise_distance_field(const float* m, int w, int h, float* out, const vnoise_distance_t* dp)`: the exact Euclidean distance between cell centers to the set `m >= threshold` (`outside`), to its complement (`inside`), or `signed` (positive inside minus half a cell, negative outside plus half a cell). Outputs SHALL be `min(d, range) / range` (signed: `0.5 + 0.5 * clamp(d / range, -1, 1)`), with `range <= 0` meaning the largest distance found. `edge` SHALL make the outside of the matrix part of neither set, the complement (`below`) or the set (`above`). A cell with no target SHALL read 1 (signed: 0 or 1). The cost SHALL be linear in the cells.

#### Scenario: Exact distances
- **WHEN** the distance to a single cell and the distances on random sets are computed
- **THEN** they equal the brute-force Euclidean distances within 1e-5 of the range

#### Scenario: Coast
- **WHEN** the signed distance of one land cell is computed with range 20
- **THEN** the land cell is above 0.5, the sea below, and its neighbor reads `0.5 - 0.5 * 0.5 / 20`

#### Scenario: Matrix edge
- **WHEN** an all-land matrix is measured `inside` with `edge = "below"`
- **THEN** each cell reads its distance to the nearest point just outside the matrix

### Requirement: Slope
The library SHALL export `vnoise_slope(const float* m, int w, int h, float* out, const vnoise_slope_t* sp)` with Horn's 3 x 3 gradient (clamped edges) on heights scaled by `relief * max(w, h)`: `angle` (`atan(g) / 90°`), `gradient` (`min(g / range, 1)`), `aspect` (downhill direction, 0..1 one turn clockwise from +x; flat cells 0), `dx` and `dy` (`0.5 + 0.5 * clamp(component / range)`) and `curvature` (`0.5 + 0.5 * clamp(Laplacian * scale / range)`, concave above 0.5).

#### Scenario: Plane
- **WHEN** a plane rising east is analyzed
- **THEN** the angle is its exact slope angle, the aspect is 0.5 (downhill west), `dx` is above 0.5 and `dy` is 0.5

#### Scenario: Bowl
- **WHEN** a paraboloid bowl is analyzed with `curvature`
- **THEN** its center is above 0.5

### Requirement: Flow accumulation
The library SHALL export `vnoise_flow(const float* m, int w, int h, const vnoise_flow_t* fp, const float* rain, const vnoise_flow_out_t* out)`: over the priority-flooded heights (outlets as in terrain plans), every cell SHALL add its rain (1 without a rain matrix) to the cells downstream, along D8 receivers or shared among the lower neighbors in proportion to `slope^exponent` (MFD). `flow` SHALL be scaled `log`, `linear` or by `range`; `filled` SHALL receive the filled heights and `lake` 1 where they exceed the heights by more than `lake_depth`.

#### Scenario: Peaks and valleys
- **WHEN** an island and a valley are routed
- **THEN** a peak receives only its own rain, and the valley axis has the most flow across the valley

#### Scenario: Pits and rain
- **WHEN** a single pit is routed, and an island with rain 0.5 everywhere
- **THEN** the pit is filled to its rim and marked as a lake, and the peak's accumulation is 0.5

### Requirement: Analysis in Lua
The binding SHALL provide `vnoise.distance_field(m, w, h, spec)`, `vnoise.slope(m, w, h, spec)` and `vnoise.flow(m, w, h, spec)` (returning flow, and the filled heights, lake mask and wetness index (`twi = true`, with `relief`, `epsilon` > 0 and `twi_range`) when asked), raising errors for unknown mode names and a non-positive `epsilon`.

#### Scenario: Unknown mode
- **WHEN** `distance_field` is called with `mode = "nope"`
- **THEN** it raises an error naming the distance mode

### Requirement: Topographic wetness index
The library SHALL export `vnoise_flow_twi(const float* m, int w, int h, const vnoise_flow_t* fp, const vnoise_twi_t* tp, const float* rain, const vnoise_flow_out_t* out, float* twi)`: the outputs of `vnoise_flow`, unchanged, and in `twi` the index `ln(A / tan(beta))`, A the accumulation of `fp`'s method in cells of rain, tan(beta) the steepest descent to an 8-neighbor on the unfilled heights in cells (`relief`, at least `epsilon`), as `clamp(twi / range, 0, 1)` or, with `range <= 0`, stretched over the matrix to 0..1.

#### Scenario: Valleys and crests
- **WHEN** a valley and a ridge are analyzed
- **THEN** the valley axis has a higher index than its sides and grows downstream, and a crest has a lower index than the foot of its slope

#### Scenario: Exact values
- **WHEN** a plane is routed with D8, edge outlets and `twi_range` 10
- **THEN** a cell draining n cells reads `ln(n / tan(beta)) / 10`, and with `twi_range` 0 the matrix spans exactly 0..1

#### Scenario: Unchanged flow
- **WHEN** a matrix is routed with and without the wetness index
- **THEN** the flow, filled heights and lake mask are identical
