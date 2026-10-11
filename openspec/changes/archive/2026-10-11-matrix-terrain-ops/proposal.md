## Why

The terrain plan (change `terrain-topography`) generates a whole world automatically: it decides where mountains rise and where rivers flow. Map authoring needs the opposite: building an elevation matrix step by step, and choosing where things go. The author places a mountain range along a drawn line or a volcano at a point, then adds a river from a chosen source or a few random ones. Each step reads the current matrix and writes a new one, with values always in 0..1.

These operations act on a **finite matrix** (a working-resolution map), not on infinite per-chunk noise. A river from a chosen source has to follow the slope across the whole matrix. Most of the machinery already exists inside the plan (priority-flood, routing, stream-power erosion, Chaikin smoothing), but it is tied to automatic generation. This change exposes it, together with new placeable features, as standalone matrix operations. The first consumer is Ludum's Map Editor.

## What Changes

- **Matrix convention.** A matrix is a row-major `float[w * h]`. Positions are given in matrix cells (floats). Every operation keeps the values in 0..1 and depends only on its inputs, its parameters and its seed, so results are reproducible.
- **Placeable features** (`vnoise_stamp`), blended into the matrix with `add`, `sub`, `max`, `min` or `replace` (weighted by the footprint):
  - `cone` (volcano, with an optional crater);
  - `crater` (a raised rim around a depression);
  - `mesa` (a flat top with steep sides);
  - `basin` (a smooth depression);
  - `dome` (a smooth bulge).

  Each has a center, radii, a rotation and a height. A seeded noise roughens its outline and its surface.
- **Path features** (`vnoise_path_feature`) along a polyline (smoothed internally):
  - `ridge`: a mountain range, with height tapering at the ends, ridged peaks and spurs from seeded noise, and a width and a profile;
  - `valley`: a carved trough;
  - `escarpment`: a step that raises one side of the line.
- **Rivers on a matrix:**
  - `vnoise_river` traces from a source down the steepest descent. It breaches depressions through their lowest spill point with a bounded local flood. It stops at the sea level, at the matrix edge, or when it joins an existing river (the river mask). It carves a channel whose width and depth grow along its course, with a bed that never rises downstream. It writes the river mask and returns the polyline.
  - `vnoise_river_sources` picks N seeded sources above a minimum elevation, with a minimum spacing between them.
- **Matrix filters:**
  - `vnoise_erode_matrix`: stream-power erosion and hillslope diffusion on the matrix itself, reusing the plan's implementation. Matrices above one million cells are eroded at a reduced resolution, and the height change is upsampled back.
  - `vnoise_apply_stages`: runs pipeline stages (point ops and kernels) on an existing matrix, with edge-extended borders, so every existing operation works on matrices.
  - `vnoise_resample`: bilinear or bicubic scaling between matrix sizes, for previews and for later scaling to a map.
- Lua wrappers for each of the above (`vnoise.stamp`, `vnoise.path_feature`, `vnoise.river`, `vnoise.river_sources`, `vnoise.erode`, `vnoise.apply_stages`, `vnoise.resample`), plus tests, README sections and a LÖVE example.

Nothing existing changes. The plan keeps its behavior; its internals are moved into a shared module so the plan and the matrix operations use the same code.

## Capabilities

### New Capabilities
- `matrix-features`: point stamps and path features on a finite matrix, their blends, and their seeded roughness.
- `matrix-rivers`: river tracing from a source (depression breaching, junctions, carving, mask, polyline) and seeded source selection.
- `matrix-filters`: matrix erosion, pipeline stages on matrices with edge-extended borders, and resampling.

### Modified Capabilities
None. `terrain-plan` keeps its requirements. Its implementation shares code with `matrix-filters`.

## Impact

- C++: new `cpp/src/matrix_features.cpp`, `matrix_rivers.cpp`, `matrix_filters.cpp`, and `cpp/src/hydrology.{h,cpp}`. The flood, routing, accumulation, erosion and Chaikin code moves there from `terrain_plan.cpp`, which then uses it.
- Public header `vnoise.h`: new structs and functions. Lua binding: new wrappers.
- Tests: `tests/matrix_ops.lua` (`make test`). Docs: README. Example: `examples/matrix/`.
- Consumer: Ludum picks it up with `make build-noise`.
