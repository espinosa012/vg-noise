# terrain-detail Specification

## Purpose
Define the per-block, multi-output evaluation of a terrain plan (elevation with detail and carved river valleys, river and lake masks, flow and channel distance), all in 0..1 and dependent only on absolute cell indices.

## Requirements

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

### Requirement: Elevation composition
`elevation` SHALL be computed in three steps:
1. **Macro**: bicubic Catmull-Rom interpolation of the eroded macro height (not the filled one), clamped per cell to the minimum and maximum of the four surrounding nodes, so it never overshoots.
2. **Detail**: when `detail.source` is given (a source spec, evaluated with `fill_source` and clamped to [-1, 1]), add `n * min(a, h, 1 - h)`. `h` is the macro value and `a = detail.amplitude` (default 0.05), scaled down near rivers by `1 - detail.valley_damping * (1 - s)` (`valley_damping` default 0.7), where `s` is the valley profile below (1 away from rivers). This headroom limit keeps the value in [0, 1] without clamping.
3. **Carving**: with `d`, `b` and `w` from the river query at the cell and `V = V(w)`, set `s = smoothstep(w / 2, w / 2 + V, d)` (1 when no river is found). Where `h > b` the value SHALL become `b + (h - b) * s ^ rivers.valley_shape` (`valley_shape` default 1; values below 1 give a U-shaped profile, above 1 a V-shaped one). Inside the channel (`d <= w / 2`) the elevation SHALL therefore equal the bed `b`.

#### Scenario: Channel is the bed
- **WHEN** a cell's query gives `d <= w / 2` and the uncarved value is above `b`
- **THEN** its elevation equals `b` within 1e-5

#### Scenario: No rivers, no detail
- **WHEN** a plan has no rivers and no detail source
- **THEN** the elevation at every node cell equals that node's macro height within 1e-5

#### Scenario: Downhill along the channel
- **WHEN** the elevation is sampled at the channel cells of a river outside lake nodes, in the order of their nearest polyline parameter
- **THEN** the sequence is non-increasing within 1e-5

### Requirement: Meanders
With `rivers.meander_amp > 0` (cells, default 0), the river query point SHALL be displaced by a two-component fBm warp. The warp has frequency `rivers.meander_freq` (default 1/64), 3 octaves, and the seed of the state the plan was created with (the plan keeps its own copy of that state). Each component is clamped to `±meander_amp`. Only the river query is displaced; the macro and detail sampling are not. The channel therefore remains a continuous band whose bed is still non-increasing along the river.

#### Scenario: Warp is bounded
- **WHEN** `meander_amp = 10`
- **THEN** every cell with `river == 1` lies within `10 + w / 2 + 1` cells of the unwarped polyline

### Requirement: Hydrology outputs
- `river` SHALL be 1 where `d <= w / 2`, fade linearly to 0 at `d = w / 2 + rivers.bank` (`bank` default 1 cell), and be 0 elsewhere or with no river.
- `lake` SHALL be `smoothstep(0.25, 0.75, L)`, where `L` is the bilinear interpolation of the 0/1 lake node mask. It SHALL be 0 where the elevation is not below the bilinear lake surface.
- `flow` SHALL be `log(1 + A) / log(1 + A_max)`, where `A` is the bilinear macro accumulation (`A_max` its maximum). Inside a channel it SHALL be at least the same expression evaluated with the river's interpolated flow.
- `channel_distance` SHALL be `min(d, R) / R`, where `R = rivers.distance_range` (default 64 cells). It SHALL be 1 when no river is found.

#### Scenario: River mask matches the query
- **WHEN** `plan:query` gives `d <= w / 2` at a cell
- **THEN** that cell's `river` value is 1 and its `channel_distance` is `d / R` within 1e-5

#### Scenario: Flow at the mouth
- **WHEN** `flow` is sampled at the cells of the node with the largest accumulation
- **THEN** the value is 1 within 1e-4

### Requirement: Plan outputs as sources
The source leaf `{ "plan", plan, output = name }` SHALL evaluate `fill_terrain` with that single output, using the caller's state. It can therefore feed pipeline stages (kernels, masks, curves) and combinators like any other leaf.

#### Scenario: Pipeline over a plan
- **WHEN** a pipeline with `source = { "plan", plan, output = "elevation" }` and stages `{ "gullies" }` is filled as one block and as four blocks
- **THEN** both results agree within 1e-5

### Requirement: Fill cost
Filling a 64 x 64 block with all five outputs and a 6-octave fBm detail source SHALL take under 2 ms on a current desktop CPU with an optimized build. The cost SHALL not depend on the total number of rivers, only on those indexed in the block's buckets. The test suite SHALL report the time.

#### Scenario: Fill time reported
- **WHEN** `make test` runs the terrain tests
- **THEN** the mean fill time of 64 x 64 blocks is printed
