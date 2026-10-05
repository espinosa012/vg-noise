## Why

Consumers (the ludum map editor and its in-game elevation layer) need to post-process noise values with an ordered chain of math operations (remap to 0-1, scale, offset, contrast, and more later). Doing it per value in Lua duplicates the logic between the image preview path and the grid path and costs an extra pass; doing it in the library gives one implementation, used by every fill, in the same pass as the noise evaluation.

## What Changes

- New C type `vnoise_op_t` (`int op; float p[4];`) and op ids `VNOISE_OP_REMAP`, `VNOISE_OP_SCALE`, `VNOISE_OP_OFFSET`, `VNOISE_OP_CONTRAST`; the id space leaves room for future ops.
- New `vnoise_apply_ops(v, ops, n, clamp01)` for a single value and `vnoise_map_buffer(buf, count, ops, n, clamp01)` to transform a float buffer in place.
- New `fbm2/ridge2/turb2_fill_imagedata_ops_rgba8` variants: evaluate noise, apply the op chain, clamp to 0-1 and write RGBA8 in one pass.
- Lua binding: op constants and names, `vnoise.compile_ops(list)` (Lua list → reusable cdata array), `vnoise.apply_ops(v, ops, clamp)`, `opts.ops` / `opts.clamp` on `fill_grid`, and `opts.ops` on `fill_imagedata` (prepended with `remap(lo, hi)`).
- New `tests/value_ops.lua` that runs against the built library.
- Existing exported functions keep their signatures and output (no ABI break): `fill_imagedata` without `opts.ops` produces bit-identical pixels.

## Capabilities

### New Capabilities
- `noise-value-ops`: ordered value-operation chains (op set and semantics, single-value and buffer application, fused image fill, Lua binding).

### Modified Capabilities
<!-- None: the existing capabilities (noise-imagedata, noise-lua-binding) keep their behavior; the new entry points are additive. -->

## Impact

- `cpp/include/vnoise/vnoise.h`, new `cpp/src/value_ops.cpp`, `cpp/src/fill_imagedata.cpp`.
- `lua/vnoise.lua` (cdef + helpers). Downstream copies (ludum's root `vnoise.lua`) pick it up through `make build-noise`.
- `tests/value_ops.lua`, `README.md`.
