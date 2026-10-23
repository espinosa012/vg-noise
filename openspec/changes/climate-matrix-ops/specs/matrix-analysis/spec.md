## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Analysis in Lua
The binding SHALL provide `vnoise.distance_field(m, w, h, spec)`, `vnoise.slope(m, w, h, spec)` and `vnoise.flow(m, w, h, spec)` (returning flow, and the filled heights, lake mask and wetness index (`twi = true`, with `relief`, `epsilon` > 0 and `twi_range`) when asked), raising errors for unknown mode names and a non-positive `epsilon`.

#### Scenario: Unknown mode
- **WHEN** `distance_field` is called with `mode = "nope"`
- **THEN** it raises an error naming the distance mode
