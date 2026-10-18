# matrix-river-network Specification

## Purpose
TBD - created by archiving change matrix-landform-ops. Update Purpose after archive.

## Requirements

### Requirement: River network
The library SHALL export `int vnoise_river_network(float* height, int w, int h, const vnoise_network_t* np, const float* rain, const vnoise_network_out_t* out)`. Over the D8 drainage of the priority-flooded heights, every cell above `sea_level` whose accumulated rain reaches `min_flow` SHALL be a channel cell. Rivers SHALL be built from the unassigned channel cell with the most flow, upstream along the unassigned donor with the most flow, and SHALL end at their receiver: an outlet (sea or edge) or a cell of an earlier river. Rivers with fewer than `min_length` own cells SHALL be skipped. Width and depth SHALL be `x0 + x_k * sqrt(A / min_flow - 1)` up to their maximum; the bed (filled surface minus depth) SHALL never rise downstream, and a tributary's bed SHALL not go below the stem's bed where it joins. Channels SHALL be carved and written to the mask as `vnoise_river` does (Chaikin smoothing, valley profile, bank fade, carving only lowers); lake cells connected to a river SHALL be marked 0.5 in the mask and raised to their surface with `fill_lakes`. It SHALL return the number of rivers and write the log-normalized flow and the polylines when asked.

#### Scenario: Island network
- **WHEN** a noisy island is processed with a sea level
- **THEN** several rivers are traced, every one ends at the sea, the edge or a river, the values stay in 0..1 and no cell is raised

#### Scenario: Order and profile
- **WHEN** the rivers of an island are listed
- **THEN** the first (main) river descends to its mouth and is at least as wide at its end as the last one

#### Scenario: Parameters
- **WHEN** `min_flow` grows, or the rain is 0 everywhere
- **THEN** there are fewer rivers, or none

#### Scenario: Lakes
- **WHEN** a valley with a basin on the way is processed with `fill_lakes`
- **THEN** the basin is marked as a lake in the mask

### Requirement: River network in Lua
The binding SHALL provide `vnoise.river_network(height, w, h, spec, mask)` returning the rivers (`{ points, width }`, main stems first), the mask and the flow (when `spec.flow`), with defaults `min_flow = max(16, w * h / 2000)`, `width0` 1, `width_k` 0.5, `max_width` 8, `depth0` 0.004, `depth_k` 0.002, `max_depth` 0.03, `valley` 4, `smooth` 2, `min_length` 4.

#### Scenario: Deterministic
- **WHEN** the same matrix is processed twice
- **THEN** the river count and the carved matrices are identical
