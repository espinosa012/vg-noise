## MODIFIED Requirements

### Requirement: Multi-output block fill
The Lua binding SHALL provide `vnoise.fill_terrain(state, plan, opts)` with `opts = { c0, r0, w, h, outputs = { names... }, out = { name = float[w*h] } }`. `outputs` defaults to `{ "elevation" }`. It SHALL return a table that maps each requested output name to a `float[w * h]` buffer for the cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)`. The outputs SHALL be `elevation`, `river`, `lake`, `flow` and `channel_distance`. An unknown name SHALL raise an error that names it. Every value of every output SHALL lie in [0, 1]. Every value SHALL depend only on the cell's absolute index, the state and the plan, so any tiling of a region SHALL equal one call over it within 1e-5. Cells outside the plan extent SHALL be defined: the macro grid is extended by clamping to its edge nodes, and only indexed rivers apply. The C side SHALL export `vnoise_plan_fill(const vnoise_plan_t*, int c0, int r0, int w, int h, const float* detail, const vnoise_terrain_out_t* out)`, with `vnoise_terrain_out_t { float* elevation; float* river; float* lake; float* flow; float* channel_distance; }`, where a NULL output is skipped and `detail` is the detail source block, or NULL for none.

#### Scenario: Unknown output
- **WHEN** `outputs = { "elevation", "snow" }`
- **THEN** `fill_terrain` raises an error that names `snow`

#### Scenario: Tiling
- **WHEN** all five outputs are filled over 128 x 128 cells crossed by a river, and again as sixteen 32 x 32 blocks
- **THEN** every value of every output agrees within 1e-5

#### Scenario: Range
- **WHEN** all outputs are filled over a 512 x 512 region of a plan with strong detail (`detail.amplitude = 0.3`)
- **THEN** every value lies in [0, 1]
