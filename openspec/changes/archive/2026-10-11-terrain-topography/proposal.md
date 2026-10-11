## Why

vnoise can make convincing textures, but not convincing terrain. One fractal per pipeline gives hills without structure: there are no mountain ranges, no valleys shaped by water, and no rivers. Rivers are the hard part. A channel that runs downhill from its source to the sea is a property of the whole map, so no per-cell or per-kernel operation can produce it. Games built on the library (the first is Ludum, which streams a finite map of up to 16384 x 16384 cells in 64 x 64 chunks) need elevation maps that look plausible and are usable for gameplay. Those maps must keep the two library conventions: values in 0..1, and a cell's value depends only on its absolute index.

This change lays a topographic foundation that later work can extend. It adds new local building blocks and a hierarchical terrain plan. The plan solves the global problems once, on a coarse grid. Detail is then added per block, by absolute cell.

## What Changes

- **Cellular (Worley) noise**: F1, F2, F2 - F1 and per-cell value, with configurable jitter and fractal sums, normalized to 0..1. Use it for ridge networks, plateaus and basins.
- **Terrain fractals**: analytic gradients for 2D simplex, and a derivative-damped fBm in which slopes suppress the finer octaves. This gives smooth valleys and rough peaks.
- **Generic sampler entry point**: a `vnoise_sampler_t` and `vnoise_fill_sampler` replace the growing list of `(mode, octaves, lac, gain)` arguments for the new modes. Existing functions stay unchanged.
- **Erosion filter**: a pipeline stage (`gullies`) that carves branching gully patterns aligned with the downhill direction of whatever it receives. It is analytic, with radius 1, and is evaluated by absolute cell.
- **Source composition**: a pipeline can take a `source` tree instead of a single fractal. Leaves are samplers with their own domain and point ops, or terrain plan outputs. Nodes combine leaves with add, mul, min, max, lerp and similar operations. Pipelines without `source` behave exactly as before.
- **Terrain plan** (`vnoise.terrain_plan`): an immutable per-world object over a finite extent. It samples a coarse macro height and uplift field from source trees. It runs stream-power erosion with uplift and hillslope diffusion, fills depressions with priority-flood, computes D8 flow directions and flow accumulation, marks lakes, and extracts the river network as polylines (smoothed, with width and bed height that never rise downstream). The polylines are held in a spatial index.
- **Terrain detail fill** (`vnoise.fill_terrain`): fills a block of absolute cells with several outputs. The outputs are `elevation`, `river`, `lake`, `flow` and `channel_distance`, all in 0..1. Elevation is the smooth interpolated macro height, plus headroom-limited detail, minus carved river valleys (with meanders from a bounded domain warp). A plan output can also be a leaf of a pipeline source.
- **Presets**: Lua helpers that build typical source trees (continent mask, mountain belts from masked ridged and cellular noise) for the plan.
- Tests (`tests/terrain.lua`), README documentation, and a terrain preview in the LÖVE example.

No breaking changes: every existing C function, Lua function and pipeline spec keeps its behavior.

## Capabilities

### New Capabilities
- `noise-cellular`: Worley/cellular noise (F1, F2, edge, cell value) as a sampler with jitter and fractal sum, normalized to 0..1.
- `noise-terrain-fractals`: Analytic simplex gradients, derivative-damped fBm, the generic sampler entry point, and the `gullies` erosion filter stage.
- `noise-sources`: Source trees (sampler and plan leaves, combinator nodes) evaluated per block by absolute cell, plus terrain presets.
- `terrain-plan`: The hierarchical plan: macro grid, stream-power erosion, priority-flood, D8 flow, flow accumulation, lakes, river network extraction and its spatial index.
- `terrain-detail`: Per-block multi-output evaluation of a plan (elevation with detail and carved rivers, river and lake masks, flow, channel distance) under the 0..1 and absolute-index conventions.

### Modified Capabilities
- `noise-pipeline`: Pipelines accept an optional `source` tree in place of the single sampler. Kernel stages receive the absolute cell origin of their input, which the new `gullies` stage needs.

## Impact

- C++: new `cpp/src/cellular.cpp`, `sampler.cpp`, `gullies.cpp`, `sources.cpp` (combinators), `terrain_plan.cpp`, `terrain_fill.cpp`, and simplex gradient code in `simplex.cpp`. The public header `vnoise.h` gets new structs, constants and functions; the plan is an opaque handle with create/destroy.
- Lua binding `lua/vnoise.lua`: new functions (`fill_sampler`, `compile_source`, `terrain_plan`, `fill_terrain`, `plan:rivers()`, presets), new pipeline stage, `source` support in `compile_pipeline`/`fill_pipeline`.
- Tests: new `tests/terrain.lua`, wired into `make test`.
- Docs: README; LÖVE example.
- Consumers: Ludum is not changed by this change. It will pick up the new library with `make build-noise` and integrate it later.
