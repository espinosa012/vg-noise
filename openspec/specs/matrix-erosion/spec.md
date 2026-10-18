# matrix-erosion Specification

## Purpose
TBD - created by archiving change matrix-landform-ops. Update Purpose after archive.

## Requirements

### Requirement: Hydraulic erosion
The library SHALL export `vnoise_erode_hydraulic(float* m, int w, int h, const vnoise_hydraulic_t* hp, const float* hardness, const float* rain, float* change_out)`. It SHALL simulate `droplets` seeded droplets on heights scaled by `relief * max(w, h)`: each starts at a random point (accepted with probability `rain` there when given), moves one cell per step along the inertia-blended downhill direction, carries up to `max(-dh, min_slope) * speed * water * capacity`, erodes (rate `erode`, over a disc of `radius` cells, scaled by `1 - hardness`, never below 0) or deposits (rate `deposit`; climbing fills the step behind), evaporates `evaporation` of its water per step and lives `lifetime` steps. A droplet SHALL drop its load where it reaches heights below `sea_level`, leaves the matrix or dries out. Unchanged cells SHALL keep their value; all values SHALL end in 0..1. `change_out`, when given, SHALL receive `0.5 + 0.5 * dz / max|dz|`.

#### Scenario: Material moves, not disappears
- **WHEN** a noise matrix is eroded with the defaults
- **THEN** it changes, stays in 0..1, its total changes by less than 2%, and the change map has values above and below 0.5

#### Scenario: Determinism
- **WHEN** a matrix is eroded twice with seed 2 and once with seed 3
- **THEN** the first two results are identical and differ from the third

#### Scenario: Hardness and rain
- **WHEN** the hardness is 1 everywhere and deposition 0, or the rain is 0 everywhere
- **THEN** no cell is lowered, or the matrix is unchanged

#### Scenario: Sea
- **WHEN** an island is eroded with a sea level
- **THEN** the seabed far from the coast is unchanged and some cells below the sea level gain sediment

### Requirement: Thermal erosion
The library SHALL export `vnoise_erode_thermal(float* m, int w, int h, const vnoise_thermal_t* tp, const float* hardness)`. In each of `iterations` synchronous passes, a cell whose slope to an 8-neighbor (heights scaled by `relief`) exceeds `tan(talus)` SHALL move `rate` times half its steepest excess drop, times `1 - hardness`, shared among its steep neighbors in proportion to their excess. It SHALL stop early when nothing moves. Material SHALL be conserved up to the final clamp, and unchanged cells SHALL keep their value.

#### Scenario: Cliff relaxes
- **WHEN** a step from 0.1 to 0.9 is eroded with talus 30 for 2000 passes
- **THEN** the total is conserved within 0.1% and the steepest slope is below 33 degrees

#### Scenario: Stable ground
- **WHEN** a flat matrix, or a cliff with hardness 1, is eroded
- **THEN** it is unchanged

### Requirement: Erosion in Lua
The binding SHALL provide `vnoise.erode_hydraulic(m, w, h, spec)` (droplets from `density` per cell, default 0.3; returns the change map when `spec.change`) and `vnoise.erode_thermal(m, w, h, spec)` (iterations 50, talus 35, rate 0.5, relief 0.05), both in place, with `hardness` and (hydraulic) `rain` matrices.

#### Scenario: Large matrix
- **WHEN** a 1024 x 1024 matrix is eroded by each
- **THEN** both complete and the tests report the time
