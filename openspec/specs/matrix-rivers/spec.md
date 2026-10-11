# matrix-rivers Specification

## Purpose
Define rivers traced on a finite matrix from chosen or seeded random sources: steepest descent with bounded breaching, junctions, lakes, a monotone carved bed and the river mask.
## Requirements
### Requirement: River from a source
The library SHALL export `int vnoise_river(float* height, int w, int h, float sx, float sy, const vnoise_river_t* rp, float* mask, float* out_points, int max_points)`. Its parameters are: `sea_level`, `width0`, `width_growth`, `max_width`, `depth0`, `depth_growth`, `max_depth`, `valley`, `valley_shape`, `bank`, `breach_radius` (default 64), `smooth` and `max_length`. Starting at the source cell, it SHALL follow the steepest descent over the 8 neighbors.
- **At a pit:** it SHALL run a priority-flood from the pit, bounded by `breach_radius`, and continue along the spill path to the first cell lower than the pit. If the flood exceeds the bound, the river SHALL end there, and the flooded cells SHALL be marked as a lake in the mask (0.5).
- **Termination:** at a cell below `sea_level`, at the matrix edge, at a cell whose mask is ≥ 0.75 (a junction with an existing river), or after `max_length` cells.
- **Bed and channel:** the traced path SHALL be smoothed. Its bed SHALL be the path height minus a depth that grows along the course (capped), made non-increasing downstream with a running minimum. Channel width SHALL grow from `width0` by `width_growth` per cell, up to `max_width`.
- **Carving:** for cells near the path, `height = min(height, bed + (height - bed) * s^valley_shape)`, with `s = smoothstep(width/2, width/2 + valley, d)`. Channel cells SHALL get `mask = 1`, fading to 0 over `bank`.
- **Output:** it SHALL write up to `max_points` smoothed points as `x, y` pairs, and return their count (0 if the source is outside the matrix or already below sea level).

#### Scenario: Downhill to the sea
- **WHEN** a river starts at the top of a matrix that slopes down to the bottom edge, with `sea_level = 0.2`
- **THEN** it ends at a cell below 0.2 or at the bottom edge, its points move downhill, and the matrix heights along its points never rise

#### Scenario: Breaching a pit
- **WHEN** the slope has a small closed pit on the way
- **THEN** the river crosses the pit's rim through its lowest spill point and continues down the slope

#### Scenario: Lake when trapped
- **WHEN** the source lies in a closed basin wider than `breach_radius`
- **THEN** the river ends in the basin, and the basin cells in the mask have value 0.5

#### Scenario: Junction
- **WHEN** a second river is traced toward the channel of a first one
- **THEN** it stops at the first channel, and its last bed value is not lower than the first channel's height there

#### Scenario: Channel mask
- **WHEN** a river is traced
- **THEN** every cell within half the channel width of the path has mask 1

### Requirement: Random river sources
The library SHALL export `int vnoise_river_sources(const float* height, int w, int h, int count, float min_elev, float min_spacing, unsigned long long seed, float* out_xy)`. It SHALL pick up to `count` seeded positions, weighted by `height - min_elev` (cells below `min_elev` excluded), at least `min_spacing` apart. It SHALL stop after a fixed attempt budget, and return how many positions it found.

#### Scenario: Spacing and elevation
- **WHEN** 10 sources are picked with `min_elev = 0.5` and `min_spacing = 30`
- **THEN** every source lies on a cell ≥ 0.5, and every pair is at least 30 cells apart

#### Scenario: Seeded
- **WHEN** the same call is repeated with the same seed
- **THEN** the same sources are returned

### Requirement: River wrappers in Lua
The Lua binding SHALL provide `vnoise.river(height, w, h, sx, sy, spec, mask)`, returning the point list as a Lua array `{ x1, y1, ... }`, and `vnoise.river_sources(height, w, h, spec)`, returning `{ { x, y }, ... }`. Both SHALL have defaults for every optional field.

#### Scenario: Wrapper defaults
- **WHEN** `vnoise.river` is called with an empty spec on a sloped matrix
- **THEN** it returns at least two points and modifies the mask

