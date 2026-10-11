## 1. Gradients and generic sampler

- [x] 1.1 Add `simplex2_deriv` and `perlin2_deriv` (analytic gradients) to `simplex.cpp`/`perlin.cpp` and export them in `vnoise.h`
- [x] 1.2 Add `vnoise_sampler_t`, the new `VNOISE_MODE_*` constants and `vnoise_fill_sampler` (`cpp/src/sampler.cpp`), sharing the domain mapping with `vnoise_fill_domain` so modes 0..2 stay bit-identical
- [x] 1.3 Implement the `DAMPED` mode (derivative-damped fBm over Perlin/Simplex 2D)
- [x] 1.4 Lua: add the `fill_sampler` cdefs and wrapper with kinds, defaults and errors for unknown kinds

## 2. Cellular noise

- [x] 2.1 Implement `cellular2_eval` (`cpp/src/cellular.cpp`): hashed jittered feature points, exact F1/F2 search, normalized F1/F2/EDGE/VALUE
- [x] 2.2 Wire the `CELL_F1`..`CELL_VALUE` modes into `vnoise_fill_sampler` with fractal weighted averaging
- [x] 2.3 Expose the Lua kinds `cell_f1`, `cell_f2`, `cell_edge`, `cell_value`

## 3. Source trees and pipeline integration

- [x] 3.1 Add `vnoise_combine(dst, src, count, op, weight)` (add, mul, min, max, sub, abs, pow, lerp helpers) in `cpp/src/sources.cpp`
- [x] 3.2 Lua: `compile_source` (validation, compiled-tree marker, per-leaf states for `seed`, op chains per node) and `fill_source` (buffer reuse, optional clamp)
- [x] 3.3 Pipeline leaf (`fill_pipeline` with `clamp = false`) and the plan leaf hook (resolved in group 7)
- [x] 3.4 `compile_pipeline`/`fill_pipeline`: optional `source` (error when combined with `domain`), `kind` may be nil, kernel `run` receives `(c0, r0, state)`; legacy output unchanged
- [x] 3.5 Presets `vnoise.presets.continent` and `vnoise.presets.mountain_belts`, producing source specs in 0..1

## 4. Gullies erosion filter

- [x] 4.1 Implement `vnoise_gullies(src, sw, sh, dst, c0, r0, state, scale, strength, octaves, gain, sharpness)` (`cpp/src/gullies.cpp`): central-difference gradient, analytic lattice stripes, smooth weights, radius 1
- [x] 4.2 Register the `gullies` kernel stage in the Lua pipeline with parameter validation

## 5. Terrain plan core (C++)

- [x] 5.1 Define `vnoise_plan_params_t`, the opaque `vnoise_plan_t`, and `vnoise_plan_create`/`destroy` (validation, macro grid sizes, the 1048576 node cap)
- [x] 5.2 Outlets (`edges`/`sea`/`both`, fallback to the lowest boundary node) and priority-flood with epsilon (heap plus pit queue)
- [x] 5.3 D8 steepest-descent receivers with a fixed tie order, the downstream stack order and flow accumulation
- [x] 5.4 Implicit stream-power iterations with uplift and capped linear diffusion; land rescale and clamp to keep 0..1
- [x] 5.5 Final routing and lake detection (`lake_depth`), storing H, F, A, the lake mask and the receivers
- [x] 5.6 River extraction: threshold, chains split at sources/confluences/mouths, mouth kind, Chaikin smoothing, per-vertex flow/width/bed, running minimum with tributary junction values
- [x] 5.7 Bucket spatial index over segment capsules, and the nearest-segment query (distance, bed, width, flow, polyline id) with an optional bounded meander warp
- [x] 5.8 Accessors: macro grids (`vnoise_plan_grid`), river counts and flat arrays, `vnoise_plan_query`

## 6. Terrain detail fill (C++)

- [x] 6.1 `vnoise_plan_fill`: clamped Catmull-Rom macro height, headroom-limited detail with valley damping, carving with `valley_shape`
- [x] 6.2 The `river`, `lake`, `flow` and `channel_distance` outputs; NULL outputs skipped; defensive final clamp; edge clamping outside the extent

## 7. Lua plan API

- [x] 7.1 `vnoise.terrain_plan(state, spec)`: option defaults and validation, macro sampling of the `height`/`uplift` sources through `fill_source` at node cells, create plus `ffi.gc`
- [x] 7.2 `plan:rivers()` (cached Lua tables), `plan:query(c, r)`, macro grid getters
- [x] 7.3 `vnoise.fill_terrain(state, plan, opts)`: output validation, the detail source block, buffers per output
- [x] 7.4 Resolve the `{ "plan", plan, output = name }` source leaf

## 8. Tests

- [x] 8.1 `tests/terrain.lua`: gradients against finite differences; damped with 0 damping equal to fBm; damping smoothness; sampler modes 0..2 equal to the domain fill
- [x] 8.2 Cellular: lattice/corner values, range, single octave equal to eval, fractal range
- [x] 8.3 Sources: unknown node, combinator arithmetic, leaf equal to sampler, tiling, preset ranges; pipeline with source, the domain+source error, legacy unchanged (`tests/image_ops.lua` still passes)
- [x] 8.4 Gullies: flat input unchanged, tiling, parameter errors
- [x] 8.5 Plan: grid size, missing height, determinism, no pits, bowl lake, conservation, downhill receivers, no-erosion identity, erosion carves valleys, range under strong uplift, rivers non-increasing and reaching outlets, empty network above the threshold, query on a vertex, build time printed
- [x] 8.6 Detail: unknown output, tiling of all outputs, range with strong detail, channel equal to bed, node identity without rivers/detail, downhill along the channel, meander bound, river mask/channel distance against the query, flow at the mouth, pipeline over a plan output, fill time printed
- [x] 8.7 Add `luajit tests/terrain.lua` to `make test`; run the whole suite and fix failures

## 9. Docs and example

- [x] 9.1 README: cellular, damped fBm, the sampler, sources and presets, gullies, terrain plan and detail (conventions, outputs, parameters with defaults, cost figures)
- [x] 9.2 Header comments for every new C declaration; LDoc docstrings for every new Lua function
- [x] 9.3 LÖVE example: a terrain preview mode (elevation shading plus river/lake overlay, regenerated with a key)
- [x] 9.4 Sync the delta specs into `openspec/specs/` and archive the change; commit and push to main
