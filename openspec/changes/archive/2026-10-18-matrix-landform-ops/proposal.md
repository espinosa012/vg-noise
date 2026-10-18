## Why

Ludum's Map Editor V2 builds world matrices (elevation, temperature, humidity, fertility) from blocks of noise and operations. Designing a real world with it showed what the library is missing:

- **Domain warp of matrices.** The domain warp exists only inside a sampler fill (one fBm level, fixed lacunarity and gain). A block diagram works on whole matrices, so it needs to warp an existing matrix, by another matrix or by a seeded field, and iterated warps (`f(p + a g(p + a g(p)))`) for natural coastlines and ranges.
- **Erosion that shapes slopes.** Stream-power erosion carves drainage, but there is no droplet (hydraulic) erosion for gullies, sediment fans and deltas, and no thermal erosion to relax cliffs into screes.
- **Distance to the coast.** The bounded `distance` kernel stops at 32 cells; continental shelves and climate gradients need an exact, unbounded, signed distance.
- **Slope as a matrix.** Buildability, humidity and fertility need slope, aspect and curvature maps.
- **River networks.** `vnoise_river` traces one river from a chosen source. A world needs every river at once, from the mountains to the sea, following the real drainage, with tributaries and lakes.

## What Changes

- `vnoise_domain_t` gains `warp_levels` (1..4, iterated warp), `warp_lac` and `warp_gain` (0 = the old defaults); one level with default parameters is bit-identical to before. Lua: `warp = { levels, lac, gain }`.
- `vnoise_warp_matrix` (displacement by `dx`/`dy` matrices, or a `direction` matrix with optional `strength`) and `vnoise_warp_matrix_noise` (seeded, iterated warp field); bilinear or clamped bicubic sampling. Lua `vnoise.warp`.
- `vnoise_erode_hydraulic` (seeded droplets with inertia, capacity, erosion brush, deposition, evaporation, sea stop, optional hardness and rain matrices, optional change map) and `vnoise_erode_thermal` (talus angle, rate, hardness). Heights are measured in cells through `relief`, so parameters do not depend on the resolution. Lua `vnoise.erode_hydraulic`, `vnoise.erode_thermal`.
- `vnoise_distance_field`: exact Euclidean distance transform (outside, inside, signed; range or max normalization; matrix edge as either side). Lua `vnoise.distance_field`.
- `vnoise_slope`: Horn gradient as angle, gradient, aspect, dx, dy, or Laplacian curvature. Lua `vnoise.slope`.
- `vnoise_flow`: D8 or multiple-flow-direction accumulation over the depression-filled matrix, with optional rain, filled heights and lake mask. Lua `vnoise.flow`.
- `vnoise_river_network`: every river whose accumulated rain reaches `min_flow`, main stems first, tributaries joined at the stem's bed, width and depth from the flow, lakes crossed at their surface, one carving pass over a segment index; mask, flow and polylines out. Lua `vnoise.river_network`.
- Tests (`tests/landforms.lua`, in `make test`), README section, header comments.

## Capabilities

### New Capabilities
- `matrix-warp`: warping a matrix by displacement matrices or a seeded iterated warp field.
- `matrix-erosion`: hydraulic (droplet) and thermal (talus) erosion on a matrix.
- `matrix-analysis`: exact distance fields, slope/aspect/curvature, flow accumulation.
- `matrix-river-network`: whole river networks carved from the drainage of a matrix.

### Modified Capabilities
- `noise-domain`: iterated warp levels and configurable warp lacunarity and gain.

## Impact

New C sources (`matrix_analysis.cpp`, `matrix_erosion.cpp`, `matrix_network.cpp`), `domain.cpp`, `vnoise.h`, `lua/vnoise.lua`. `vnoise_domain_t` grows by three fields at its end: consumers that copy the binding and the library together (Ludum's `make build-noise`) are unaffected, and zero-initialized structs keep the old behavior. Every new function respects the register-only argument rule (`tests/abi.lua`).
