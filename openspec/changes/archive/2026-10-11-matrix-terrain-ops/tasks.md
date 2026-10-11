## 1. Shared hydrology

- [x] 1.1 Dump the reference plan's grids and rivers (`tests/terrain.lua` world spec) before any change.
- [x] 1.2 Move `Grid`, priority-flood, routing, stack order, accumulation, the stream-power step, diffusion and Chaikin from `terrain_plan.cpp` into `cpp/src/hydrology.{h,cpp}`; `terrain_plan.cpp` uses them. Verify the dump is bit-identical.

## 2. Features

- [x] 2.1 `vnoise_stamp` (`cpp/src/matrix_features.cpp`): the shapes, rotated elliptical distance, seeded outline and surface roughness, blends, bounding-box iteration.
- [x] 2.2 `vnoise_path_feature`: Chaikin smoothing, segment bucket index, distance/arc-parameter/side, ridge (envelope, cross profile, ridged peaks, spur warp), valley, escarpment, blends.
- [x] 2.3 Header declarations with comments; Lua wrappers `vnoise.matrix`, `vnoise.stamp`, `vnoise.path_feature` with name maps, defaults and errors.

## 3. Rivers

- [x] 3.1 `vnoise_river` (`cpp/src/matrix_rivers.cpp`): steepest descent, bounded local breaching with spill path, lake fallback, termination rules, smoothing, monotone bed with growing depth, carving and mask, points out.
- [x] 3.2 `vnoise_river_sources`: weighted seeded draws with spacing and an attempt budget.
- [x] 3.3 Lua wrappers `vnoise.river`, `vnoise.river_sources`.

## 4. Filters

- [x] 4.1 `vnoise_erode_matrix` (`cpp/src/matrix_filters.cpp`) over the shared hydrology, with the downsample-and-delta path above 1M cells and the optional flow output; Lua `vnoise.erode`.
- [x] 4.2 `vnoise.apply_stages` (padding with clamped edges, compiled pipeline stages, clamp).
- [x] 4.3 `vnoise_resample` (bilinear, clamped bicubic); Lua `vnoise.resample`.

## 5. Tests, docs, example

- [x] 5.1 `tests/matrix_ops.lua`: every scenario of the three specs, plus timings (a 1024² stamp, path, river and erosion; 2048² erosion). Add it to `make test`.
- [x] 5.2 README section "Matrix operations" (convention, each operation, blends, costs); header comments; LDoc docstrings.
- [x] 5.3 `examples/matrix/`: a LÖVE demo that builds a map step by step (continent, ridge along a line, volcano, erosion, random rivers) and shows each step.
- [x] 5.4 Run `make test`; sync the specs and archive the change; commit and push to `main`.
