## Why

Games using vg-noise need arbitrary transfer functions (user-drawn curves, terraces) applied in the same native op chain as the other value operations. A curve-specific op would need C code for every new curve type; a generic look-up table op lets callers sample any function in their own language.

## What Changes

- New `VNOISE_OP_LUT` (4): linear interpolation in a table of samples over `[0, 1]`, input clamped to `[0, 1]`.
- **BREAKING (ABI)**: `vnoise_apply_ops`, `vnoise_map_buffer` and the `*_fill_imagedata_ops_rgba8` fills take a `const float* data` pool argument (NULL when unused).
- Lua binding: `OP_LUT`, `{ "lut", values }` / `{ "lut", ptr, count }` entries in `compile_ops`, compiled chains carry `data`/`data_n`, all ops entry points pass the pool.

## Capabilities

### Modified Capabilities
- `noise-value-ops`: adds the LUT op, the data pool argument and the binding support.

## Impact

`cpp/include/vnoise/vnoise.h`, `internal.h`, `cpp/src/value_ops.cpp`, `fill_imagedata.cpp`, `lua/vnoise.lua`, `tests/value_ops.lua`, README. Consumers must update the binding and library together.
