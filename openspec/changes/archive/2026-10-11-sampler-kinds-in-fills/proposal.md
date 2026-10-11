## Why

The sampler kinds added by `terrain-topography` (`damped`, `cell_f1`, `cell_f2`, `cell_edge`, `cell_value`) were only reachable through `fill_sampler` and source-tree leaves. Consumers that pass a kind per fill could not use them, and a source leaf freezes frequency and octaves at compile time. The consumers are Ludum's noise editor, its level-of-detail octave dropping and stride previews, and recipe sampling.

## What Changes

- `fill_grid`, `fill_domain` and `fill_pipeline` accept every sampler kind as `kind`. For the new kinds they read `opts.jitter` and `opts.damping`, and fill through `vnoise_fill_sampler` with the same cell-to-point mapping. Classic kinds keep their dedicated native fills, so their outputs are bit-identical.
- Unknown kinds still raise an error naming them.
- README and docstrings updated; tests added to `tests/terrain.lua`.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `noise-terrain-fractals`: every per-fill entry point accepts every sampler kind (added requirement).

## Impact

Lua binding only (`lua/vnoise.lua`); no C change. Consumers: Ludum (`noise-editor-samplers`).
