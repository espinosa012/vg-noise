# terrain-plan Specification

## Purpose
Define the hierarchical terrain plan: a coarse macro grid over a finite extent with stream-power erosion, depression filling, flow routing and accumulation, lakes, and the river network with its spatial index.
## Requirements
### Requirement: Plan creation
The Lua binding SHALL provide `vnoise.terrain_plan(state, spec)`, which returns an immutable plan object whose native memory is released by the garbage collector. `spec` holds:
- `width`, `height`: the extent in cells, each 1..65536.
- `macro_cell`: the macro spacing in cells, >= 4, default 64.
- `elevation`: a source spec for the macro height, required.
- `uplift`: a source spec, optional.
- `sea_level`: in 0..1, default 0.
- `outlets`: `"edges"`, `"sea"` or `"both"`, default `"both"`.
- `erosion`, `rivers`, `detail`: option tables described in the following requirements.

The macro grid SHALL have `mw = ceil(width / macro_cell) + 1` by `mh = ceil(height / macro_cell) + 1` nodes. Node `(i, j)` lies at cell `(i * macro_cell, j * macro_cell)`. The input height SHALL be the `elevation` source sampled at the node cells (with `fill_source` and `stride = macro_cell`) and clamped to 0..1 (likewise `uplift`, default 0). `terrain_plan` SHALL raise an error for a missing `elevation`, a bad option, or `mw * mh` above 1048576.

The C side SHALL export an opaque `vnoise_plan_t`, with `vnoise_plan_create(const vnoise_plan_params_t*, const float* height, const float* uplift)` (NULL on invalid input), `vnoise_plan_destroy`, and read accessors for the macro grids and the river network.

#### Scenario: Grid size
- **WHEN** a plan has `width = 1000`, `height = 500` and `macro_cell = 64`
- **THEN** its macro grid is 17 x 9 nodes

#### Scenario: Missing elevation
- **WHEN** `terrain_plan` is called without `elevation`
- **THEN** it raises an error that names `elevation`

#### Scenario: Determinism
- **WHEN** two plans are created from equal seeds and specs
- **THEN** their macro grids and river networks are identical

### Requirement: Outlets and depression filling
Outlet nodes SHALL be the boundary nodes (`edges`), the nodes whose height is below `sea_level` (`sea`), or both. Erosion uses the outlets of the input height; the final drainage uses the outlets of the final (eroded) height. With `"sea"` and no node below sea level, the lowest boundary node SHALL be the only outlet. The plan SHALL fill depressions with priority-flood plus a minimal increment (`epsilon = 1e-6`), giving the filled height `F >= H` such that every non-outlet node has at least one 8-neighbor with strictly lower `F`. Nodes with `F - H > lake_depth` (`rivers.lake_depth`, default 0.002) SHALL be lake nodes, with lake surface `F`.

#### Scenario: No pits
- **WHEN** a plan is built from a noisy height field
- **THEN** every non-outlet node has a strictly lower 8-neighbor in `F`

#### Scenario: Bowl becomes a lake
- **WHEN** the elevation source is a bowl with a closed rim, `outlets = "edges"`, and no erosion
- **THEN** the bowl's interior nodes are lake nodes with surface equal to the rim's lowest pass height (within 1e-4)

### Requirement: Flow routing and accumulation
Each non-outlet node's receiver SHALL be the 8-neighbor with the steepest descent in `F` (drop divided by 1 or sqrt(2)). Ties SHALL be broken by a fixed neighbor order. Outlets have no receiver. The flow accumulation `A` of a node SHALL be the number of nodes (itself included) whose receiver chain passes through it.

#### Scenario: Conservation
- **WHEN** a plan is built
- **THEN** the sum of `A` over the outlet nodes equals `mw * mh`

#### Scenario: Downhill
- **WHEN** a plan is built
- **THEN** every receiver has a strictly lower `F` than its donor

### Requirement: Stream-power erosion
With `erosion.iterations > 0` (default 60), the plan SHALL run that many implicit stream-power steps (Braun-Willett, `n = 1`) over the macro grid before the final filling and routing. The drainage (depression filling, routing, accumulation and `A^m`) SHALL be recomputed before the first step and then every `erosion.reroute` steps (default 4; 1 recomputes it every step). Each step SHALL then update every non-outlet node in downstream-to-upstream order: `h = (h + dt * (U + K * A^m * h_r / L)) / (1 + dt * K * A^m / L)`. `h_r` is the receiver's updated height, `L` the distance to it in macro units, and `U` the uplift times `erosion.uplift` (default 0.002). The parameters are `erosion.k` (default 0.01), `erosion.m` (default 0.5), and `erosion.dt` (default 1). Each step SHALL then apply linear hillslope diffusion of coefficient `erosion.diffusion` (default 0.01; at most 0.25 for stability). Outlets SHALL keep their height. If the eroded land maximum exceeds 1, heights above `sea_level` SHALL be rescaled linearly from `[sea_level, max]` to `[sea_level, 1]`, and heights SHALL be clamped to >= 0, so the macro height stays in 0..1. With `iterations = 0` the macro height SHALL be the input height.

#### Scenario: No erosion
- **WHEN** a plan has `erosion.iterations = 0`
- **THEN** its macro height equals the sampled input height

#### Scenario: Erosion carves valleys
- **WHEN** a plan over a noisy ridge (with the same field as uplift) is built with 0 and with 100 iterations
- **THEN** the mean height of the nodes with the top 5% of accumulation, divided by the mean height of all nodes, is lower with 100 iterations

#### Scenario: Range
- **WHEN** a plan is built with a strong uplift (`erosion.uplift = 0.05`, 200 iterations)
- **THEN** every macro height lies in [0, 1]

### Requirement: River network
River nodes SHALL be the non-sea nodes with `A >= rivers.min_flow` (in nodes, default 32). The network SHALL be split into polylines at sources, confluences and mouths. A polyline runs from a river node with no river donor, or from just below a confluence, along receivers to the next confluence or to its mouth. The mouth is the first outlet reached: a sea or edge node, recorded as `mouth = "sea" | "edge" | "river"`. Vertices SHALL start at node cell positions and be smoothed with `rivers.smooth` (default 2) Chaikin passes that keep both endpoints. Each vertex SHALL carry:
- flow `A`, interpolated along the polyline
- width `w = min(rivers.width * sqrt(A / min_flow), rivers.max_width)` (defaults 2 and 24 cells)
- bed height `b = max(F - rivers.depth * sqrt(A / min_flow), 0)` (`depth` default 0.004, capped by `rivers.max_depth`, default 0.03)

The bed SHALL then be made non-increasing downstream with a running minimum. A tributary's last vertex SHALL equal the main river's bed at the junction, and the tributary's own running minimum SHALL take that value into account, so the bed never rises in the flow direction.

`plan:rivers()` SHALL return a Lua list of `{ points = { x1, y1, ... }, flow = { ... }, width = { ... }, bed = { ... }, mouth = ... }` in absolute cell coordinates.

#### Scenario: Rivers run downhill
- **WHEN** a plan is built
- **THEN** along every polyline the bed sequence is non-increasing

#### Scenario: Rivers reach an outlet
- **WHEN** a plan is built
- **THEN** every polyline ends at a sea or edge node or at a vertex of another polyline (its mouth)

#### Scenario: No rivers below the threshold
- **WHEN** `rivers.min_flow` exceeds `mw * mh`
- **THEN** `plan:rivers()` is empty

### Requirement: River spatial index
The plan SHALL index the river segments in a uniform bucket grid of `macro_cell` cells. Each segment SHALL be registered in every bucket that its capsule overlaps. The capsule radius is `w / 2 + V(w) + rivers.meander_amp`, where `w` is the segment's largest vertex width and `V(w) = rivers.valley * w / 2 + rivers.valley_min` is the valley half-width (`valley` default 6, `valley_min` default 8 cells). A query at a cell SHALL test only the segments of that cell's bucket. `plan:query(c, r)` SHALL return the distance `d` to the nearest river centerline (after the meander warp, see terrain-detail) and, for that point, the interpolated `bed`, `width`, `flow` and polyline index. It SHALL return `nil` when no segment is registered in the bucket.

#### Scenario: Query on a vertex
- **WHEN** a plan has `rivers.meander_amp = 0` and is queried at the cell of a river vertex
- **THEN** `d` is at most 0.5 and `bed` equals the vertex's bed within 1e-4

#### Scenario: Far from rivers
- **WHEN** the query cell is farther than every capsule radius from every river
- **THEN** the query returns `nil` or a distance larger than the valley width

### Requirement: Plan build cost
A plan with a 257 x 257 macro grid (16384 cells at `macro_cell = 64`) and 100 erosion iterations SHALL build in under 500 ms on a current desktop CPU with an optimized build. Memory SHALL be proportional to the node and segment counts, never to the cell extent. The test suite SHALL report the build time.

#### Scenario: Build time reported
- **WHEN** `make test` runs the terrain tests
- **THEN** the build time of the reference plan is printed

