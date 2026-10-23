# matrix-climate Specification

## Purpose
Define climate operations on a matrix: moisture carried by the wind with orographic precipitation (winds from a direction matrix or latitude bands), and Gaussian blurs of any width.

## Requirements

### Requirement: Moisture transport and orographic precipitation
The library SHALL export `vnoise_moisture(const float* m, int w, int h, const vnoise_moisture_t* mp, const float* src, const float* dir, const vnoise_moisture_out_t* out)`. Each cell SHALL read the moisture q one step L upwind (`inflow` outside the matrix), add `evaporation * source * L` up to `capacity` (source: `src`, else 1 below `sea_level`), and on land rain `P = q * clamp(base_rate * L + orographic * max(0, rise), 0, 1)`, `rise` the height gained over the step in cells (`relief`; heights below the sea count as the sea level), keeping `q - P`. It SHALL solve the steady state with `iterations` cycles of four Gauss-Seidel sweeps by wind quadrant, deterministically.

#### Scenario: Rain shadow
- **WHEN** a strip of land downwind of the sea is computed flat and with a ridge across the wind
- **THEN** the windward slope rains more than the same cell of the flat strip, the lee rains less, no rain falls over the sea, and the moisture decreases inland

### Requirement: Moisture outputs
`vnoise_moisture` SHALL write the non-NULL outputs: `precip` (`P / range` clamped, or divided by the largest P when `range <= 0`), `moisture` (`q / capacity`) and `fetch` (cells along the wind since the last cell with source >= 0.5, the outside counting as a source when `inflow > 0`, divided by `fetch_range` or the largest; 1 where no source lies upwind).

#### Scenario: No source upwind
- **WHEN** the only sea lies downwind of the land and `inflow` is 0
- **THEN** the land gets no rain and its fetch reads 1; with `inflow > 0` it gets rain

#### Scenario: Fetch
- **WHEN** the wind blows from a sea onto flat land
- **THEN** the fetch is 0 over the sea and n cells n cells inland (scaled by `fetch_range`)

### Requirement: Winds
The wind of `vnoise_moisture` SHALL be the unit vector of `dir` (0..1 = one turn clockwise from +x) when given, else that of the latitude band of the cell's row: with `bands[0..4]` the row fractions of the polar front, subtropical ridge, equator, ridge and polar front, easterlies (toward -x, turned `tilt` degrees toward the equator) between the ridges and beyond the fronts, westerlies (toward +x, turned toward the pole) in between. The upwind point SHALL be where the wind ray crosses the previous column or row, interpolated between two cells.

#### Scenario: Latitude bands
- **WHEN** a sea strip crosses land from top to bottom and the default bands give the winds
- **THEN** rows in the trade winds and polar easterlies rain west of the strip only, rows in the westerlies east of it only, and custom bands move the belts

#### Scenario: Tilt
- **WHEN** a source north of the equator feeds the trade winds with tilt 0 and with tilt 30
- **THEN** the wettest row downwind stays at the source's rows without tilt and moves toward the equator with it

#### Scenario: Uniform wind
- **WHEN** a uniform diagonal wind is computed with 1 and with 6 cycles
- **THEN** the results are identical

### Requirement: Large Gaussian blur
The library SHALL export `vnoise_blur_matrix(const float* src, int w, int h, float* dst, const vnoise_blur_t* bp)`: `passes` (1..8, 3 when <= 0) extended box filters per axis whose variances add up to `sigma^2` (sigma at most 16384), over the matrix extended with its border values, in O(1) per value per box regardless of sigma and without the pipelines' kernel radius limit. `sigma <= 0` SHALL copy; `dst` MAY alias `src`; values SHALL be clamped to 0..1.

#### Scenario: Matches the exact Gaussian
- **WHEN** an fBm matrix is blurred with sigma 0.6, 1.5, 3 and 6 and compared with the pipeline `gaussian` stage through `apply_stages`
- **THEN** the largest difference is below 0.015 and the RMS difference below 0.004, and more passes come closer

#### Scenario: Invariants
- **WHEN** a constant matrix and an interior impulse are blurred
- **THEN** the constant is unchanged, and the impulse keeps its mass, its center and a variance of sigma^2 per axis

#### Scenario: Sigma beyond the matrix
- **WHEN** a 96 x 80 matrix is blurred with sigma 1024
- **THEN** it is nearly constant (spread below 0.02) and in 0..1

### Requirement: Climate operations in Lua
The binding SHALL provide `vnoise.moisture(m, w, h, spec)` (returning the precipitation, and the moisture and fetch when asked; `bands` a list of five non-decreasing numbers in 0..1, else an error) and `vnoise.blur_large(m, w, h, spec)` (sigma >= 0 and passes in 1..8, else an error).

#### Scenario: Invalid bands
- **WHEN** `moisture` is called with decreasing bands or a list of one band
- **THEN** it raises an error naming the bands
