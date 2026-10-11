# matrix-features Specification

## Purpose
Define positioned edits of a finite elevation matrix: point stamps (dome, cone, crater, mesa, basin) and features along polylines (ridge, valley, escarpment), their blends and seeded roughness, with values kept in 0..1.
## Requirements
### Requirement: Matrix convention
Matrix operations SHALL work on a row-major `float[w * h]` buffer with explicit `w` and `h`. Cell `(i, j)` has its center at `(i + 0.5, j + 0.5)` in matrix coordinates, and positions and lengths SHALL be given in those units. Every operation SHALL do nothing for NULL buffers or non-positive sizes. It SHALL clamp the values it writes to 0..1, and SHALL depend only on its inputs, parameters and seed.

#### Scenario: Range
- **WHEN** any matrix operation runs on a matrix with values in 0..1, with extreme parameters (heights of 5, negative blends)
- **THEN** every value of the result lies in 0..1

#### Scenario: Determinism
- **WHEN** an operation runs twice on equal matrices with equal parameters and seed
- **THEN** both results are identical

### Requirement: Point stamps
The library SHALL export `vnoise_stamp(float* m, int w, int h, const vnoise_stamp_t* st)`. The stamp's fields are: `shape`, center `cx`, `cy`, radii `rx`, `ry`, `angle` (degrees), `height`, `roughness` (0..1), `seed`, `blend`, and shape parameters `p[4]`. The shapes SHALL be:
- `VNOISE_STAMP_DOME`: profile `(1 - d²)²`;
- `VNOISE_STAMP_CONE`: profile `1 - d`, with a crater dip inside `p[0]` times the radius when `p[0] > 0`;
- `VNOISE_STAMP_CRATER`: a rim at `1 - p[0]` and the floor at `p[1]` times the height;
- `VNOISE_STAMP_MESA`: flat to `1 - p[0]`, then a smoothstep to 0;
- `VNOISE_STAMP_BASIN`: the dome profile, applied downward.

Here `d` is the normalized elliptical distance after rotation, with the outline perturbed by seeded noise scaled by `roughness`. Profiles SHALL be 0 at `d >= 1`, so cells outside the footprint are unchanged. The blends SHALL be:
- `ADD`: `m + v`;
- `SUB`: `m - v`;
- `MAX`: `max(m, v)`;
- `MIN`: `min(m, v)`;
- `REPLACE`: `m + p * (height - m)`.

Here `v = height * profile` (with the roughness surface factor), and `REPLACE` only acts where the profile is above 0. Only cells inside the stamp's bounding box SHALL be visited.

#### Scenario: Dome peak
- **WHEN** a dome with `height = 0.4`, no roughness and blend `ADD` is stamped at the center of a constant 0.2 matrix
- **THEN** the center cell is 0.6 (within 1e-4), and cells outside the radius are 0.2

#### Scenario: Volcano crater
- **WHEN** a cone with `p[0] = 0.2` is stamped
- **THEN** the center value is lower than the value at 0.25 of the radius

#### Scenario: Mesa top
- **WHEN** a mesa with `p[0] = 0.3`, `height = 0.7` and blend `REPLACE` is stamped on a constant 0.1 matrix without roughness
- **THEN** every cell with `d <= 0.7` is 0.7 (within 1e-4)

### Requirement: Path features
The library SHALL export `vnoise_path_feature(float* m, int w, int h, const float* points, int n, const vnoise_path_t* pf)`. `points` holds `n >= 2` pairs `x, y`; the polyline is smoothed with `smooth` Chaikin passes that keep its ends. The feature's fields are: `kind`, `height`, `width` (the full cross width in cells), `taper` (0..0.5 of the length), `sharpness`, `peakiness` (0..1), `spurs` (in cells), `roughness`, `seed`, `side` (+1 or -1, for escarpments), `reach` and `blend`. The kinds SHALL be:
- `VNOISE_PATH_RIDGE`: a mountain range. Its value is `height * envelope(t) * cross(d) * peaks`. `t` is the arc-length parameter along the path, and `envelope` tapers to 0 over `taper` at both ends. `cross = (1 - (d / (width / 2))²)₊^sharpness`. `peaks` mixes 1 with seeded ridged noise along and across the path, by `peakiness`. `d` is warped by seeded fBm of amplitude `spurs`, so the flanks branch.
- `VNOISE_PATH_VALLEY`: a trough with the ridge's envelope and cross section, without peaks, subtracted from the matrix.
- `VNOISE_PATH_ESCARPMENT`: a step that raises the `side` of the line by `height * envelope(t) * smoothstep(0, width, d) * (1 - smoothstep(reach - width, reach, d))`. `reach` (default `4 * width`) bounds the raised band, so cells farther than `reach` from the line are unchanged.

Blends SHALL be as for stamps (valleys use `SUB` by default). The cost SHALL be proportional to the area of the path's bounding box grown by its width, using a bucket index of the segments.

#### Scenario: Ridge along a line
- **WHEN** a ridge with `height = 0.5`, `width = 40`, `peakiness = 0` and no spurs or roughness is drawn from `(20, 100)` to `(180, 100)` on a zero matrix
- **THEN** the cell at `(100, 100)` is 0.5 (within 1e-3), the cell at `(100, 125)` is 0, and the cells near the ends are lower than the middle

#### Scenario: Escarpment side
- **WHEN** an escarpment with `side = +1` is drawn along a vertical line on a constant matrix
- **THEN** only the cells on one side of the line rise

#### Scenario: Too few points
- **WHEN** `n < 2`
- **THEN** the matrix is unchanged

### Requirement: Feature wrappers in Lua
The Lua binding SHALL provide `vnoise.stamp(m, w, h, spec)` and `vnoise.path_feature(m, w, h, points, spec)` with named fields (`shape` / `kind` and `blend` by name: `"dome"`, `"cone"`, `"crater"`, `"mesa"`, `"basin"`, `"ridge"`, `"valley"`, `"escarpment"`, `"add"`, `"sub"`, `"max"`, `"min"`, `"replace"`), defaults for every optional field, and errors naming an unknown name or an invalid value. `vnoise.matrix(w, h, fill)` SHALL allocate a matrix.

#### Scenario: Unknown shape
- **WHEN** `vnoise.stamp` is called with `shape = "pyramid"`
- **THEN** it raises an error that names `pyramid`

