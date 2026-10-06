## Why

Procedural placement (e.g. forests in project-ludum) needs one seeded random value per integer cell over a block of cells. Calling `white2_eval` once per cell from Lua works, but a batch fill matches the rest of the library's batch APIs and amortizes the FFI round-trips.

## What Changes

- New C function `white2_fill_grid(state, out, ox, oy, w, h)`: `out[j * w + i] = white2_eval(state, ox + i, oy + j)`, bit-identical to the per-cell call, seed key derived once per call.
- New Lua binding `vnoise.fill_white(state, opts)` (`w`, `h`, `ox`, `oy`, `out`, optional `ops`/`clamp` like `fill_grid`).
- Tests in `tests/value_ops.lua` (`make test`) and README entries.

## Capabilities

### New Capabilities
- `noise-white-fill`: seeded white-noise batch fill over integer cells.

### Modified Capabilities

## Impact

Additive: `cpp/src/white.cpp`, `cpp/include/vnoise/vnoise.h`, `lua/vnoise.lua`, `tests/value_ops.lua`, `README.md`. Older bindings keep working with the new library.
