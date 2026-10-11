# noise-sources Specification

## Purpose
Define source trees that combine samplers, constants, masks, pipelines and terrain plan outputs per block by absolute cell, and the terrain presets (continent, mountain belts) built from them.
## Requirements
### Requirement: Source trees
The Lua binding SHALL provide `vnoise.compile_source(spec)`, which returns a compiled source and raises an error naming any unknown node, bad parameter or missing child. Passing an already compiled source SHALL return it unchanged. A spec is a tree of these forms:
- **Sampler leaf** `{ kind, freq, ox, oy, octaves, lac, gain, base, jitter, damping, domain = <domain spec>, seed = n, ops = <op list> }`. `kind` is any `fill_sampler` kind. `seed`, when given, gives the leaf its own state (`vnoise.new(seed)`) instead of the caller's. `ops` is a point op chain applied to the leaf's values.
- **Constant** `{ "const", v }`.
- **Pipeline leaf** `{ "pipeline", <pipeline spec>, kind = ..., <sampler opts> }`, evaluated with `fill_pipeline` (`clamp = false`).
- **Plan leaf** `{ "plan", plan, output = name }` (see terrain-detail).
- **Mask leaf** `{ "mask", <mask spec> }`: the weight of a pipeline mask (see `compile_mask`) at each cell, in 0..1; e.g. a feathered rectangle as a coast falloff.
- **Combinators** `{ "add", a, b, ..., weights = { ... } }` (weighted sum, weights default 1), `{ "mul", a, b, ... }`, `{ "min", a, b, ... }`, `{ "max", a, b, ... }`, `{ "lerp", a, b, t }` (`a + t * (b - a)`), `{ "sub", a, b }`, `{ "abs", a }`, `{ "pow", a, e }` (`max(a, 0) ^ e`).

Any node SHALL accept `ops = <op list>`, applied after the node is evaluated. Values SHALL flow unclamped between nodes.

#### Scenario: Unknown node
- **WHEN** a spec contains `{ "xor", a, b }`
- **THEN** `compile_source` raises an error that names `xor`

#### Scenario: Combinator arithmetic
- **WHEN** `{ "lerp", { "const", 0.2 }, { "const", 0.6 }, { "const", 0.25 } }` is filled
- **THEN** every value is 0.3 within 1e-6

### Requirement: Source block evaluation
`vnoise.fill_source(state, source, opts)` SHALL return a `float[w * h]` buffer for the cells `(c0 .. c0 + w - 1, r0 .. r0 + h - 1)`. `opts` holds `c0`, `r0`, `w`, `h`, `out`, `stride` (default 1: buffer cell `(i, j)` is the absolute cell `(c0 + i * stride, r0 + j * stride)`, used to sample macro grids), and `clamp` (default false), which clamps the final values to 0..1. Every cell SHALL depend only on its absolute index, so any tiling of a region SHALL equal one call over it within 1e-5. Each sampler leaf SHALL evaluate exactly as `fill_sampler` with its own parameters followed by its `ops`.

#### Scenario: Leaf equals sampler
- **WHEN** a source is a single `ridge` leaf with `ops = { { "remap", 0, 1 } }`
- **THEN** its buffer equals `fill_sampler` followed by that chain within 1e-6

#### Scenario: Tiling
- **WHEN** a tree combining a warped `fbm` leaf, a `cell_edge` leaf with its own seed and a pipeline leaf with a Gaussian is filled over 64 x 64 cells, and again as four 32 x 32 blocks
- **THEN** every cell agrees within 1e-5

### Requirement: Terrain presets
The Lua binding SHALL provide `vnoise.presets.continent(opts)` and `vnoise.presets.mountain_belts(opts)`. Each SHALL return a source spec whose values lie in 0..1, ready for a plan's `elevation` or `uplift`.
- `continent` takes `width`, `height` (the extent in cells), `freq`, `octaves`, `coast` (the fraction of the extent over which land falls toward the border, default 0.15) and `land` (the target land ratio as an offset, default 0.5). It is a warped fBm, offset by `land - 0.5` and multiplied by a feathered rectangle mask over the extent (the border falloff).
- `mountain_belts` takes `freq`, `belt_freq`, `sharpness` and `jitter`. It is ridged noise multiplied by a smooth band mask (from low-frequency `cell_edge` or fBm), so ridges form long chains instead of being spread evenly.

#### Scenario: Preset range
- **WHEN** each preset with default options is compiled and filled over 256 x 256 cells with `clamp = false`
- **THEN** every value lies in [0, 1] within 1e-5

