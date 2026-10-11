## ADDED Requirements

### Requirement: Cellular evaluation
The library SHALL export `float cellular2_eval(const noise_state_t* s, float x, float y, float jitter, int ret)`. Each integer lattice cell `(i, j)` holds one feature point at `(i + 0.5 + jitter * (u - 0.5), j + 0.5 + jitter * (v - 0.5))`, where `u` and `v` are in [0, 1) and derived from `white2_eval`-style hashes of the cell and the state seed. `jitter` SHALL be clamped to [0, 1]. Let `d1 <= d2` be the Euclidean distances from `(x, y)` to the nearest and second-nearest feature points. These SHALL be exact for any jitter in [0, 1], so the search covers enough neighbors. `ret` selects the result:
- `VNOISE_CELL_F1` (0): `min(d1, 1)`
- `VNOISE_CELL_F2` (1): `min(d2 / 1.5, 1)`
- `VNOISE_CELL_EDGE` (2): `min(d2 - d1, 1)`
- `VNOISE_CELL_VALUE` (3): a hash of the nearest feature's cell in [0, 1)

Every result SHALL be in [0, 1]. Distance ties SHALL be broken by a fixed neighbor order.

#### Scenario: Regular lattice
- **WHEN** `jitter = 0` and the point is a cell center `(3.5, 7.5)`
- **THEN** F1 is 0, F2 is `1 / 1.5` within 1e-5, and EDGE is 1 (clamped from d2 - d1 = 1)

#### Scenario: Equidistant corner
- **WHEN** `jitter = 0` and the point is a lattice corner `(3, 7)`
- **THEN** F1 is `sqrt(0.5)` within 1e-5 and EDGE is 0

#### Scenario: Range
- **WHEN** 100000 random points are evaluated with jitter 1 for every `ret`
- **THEN** every value lies in [0, 1]

### Requirement: Cellular sampler modes
`vnoise_fill_sampler` modes `CELL_F1`, `CELL_F2`, `CELL_EDGE` and `CELL_VALUE` SHALL evaluate `cellular2_eval` with the sampler's `jitter` over `octaves` octaves. Each octave scales the coordinates by `lac^o` and adds a per-octave offset. Each octave's result is weighted by `gain^o`, and the weighted sum is divided by the sum of weights, so the result stays in [0, 1]. With one octave the result SHALL equal `cellular2_eval` at the mapped point.

#### Scenario: Single octave
- **WHEN** a block is filled in mode `CELL_F1` with one octave
- **THEN** each value equals `cellular2_eval` at the cell's mapped point within 1e-6

#### Scenario: Fractal range
- **WHEN** a 256 x 256 block is filled in mode `CELL_EDGE` with 4 octaves
- **THEN** every value lies in [0, 1]
