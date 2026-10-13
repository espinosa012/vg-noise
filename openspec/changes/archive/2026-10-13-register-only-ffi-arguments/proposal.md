## Why

Ludum froze for 20 to 90 seconds or more when entering the game. With `lldb` attached to a stalled process, `vnoise_fill_domain` received an octave count of 13,282,480 instead of 4: the call came from JIT-compiled code, and `octaves` was the tenth argument, which travels on the stack on arm64 (only 8 integer/pointer arguments fit in registers). LuaJIT's JIT compiler, as shipped with LÖVE 11.5, can place stack-passed FFI arguments in the wrong slot on macOS arm64 (Apple packs stack arguments), so the callee read a neighbouring slot. Whether the call is compiled depends on how often it ran before, so the stall was intermittent (about one start in eight). Ten exported functions pass arguments on the stack: the six image fills, `vnoise_fill_domain`, `vnoise_mask_blend`, `vnoise_plan_rivers` and `vnoise_plan_fill`.

## What Changes

- **BREAKING** (C API): no exported function takes more than 8 integer/pointer or 8 float arguments, so every argument is passed in a register:
  - `vnoise_fill_domain(s, const vnoise_sampler_t* sp, out, c0, r0, w, h, d)`: mode, base, octaves, lacunarity and gain come from the sampler (`vnoise_sampler_t` moves before it in the header); modes other than fBm, ridge and turbulence do nothing.
  - `*_fill_imagedata_rgba8(..., float lo, float hi, unsigned int rgba)` and `*_fill_imagedata_ops_rgba8(..., const vnoise_chain_t* chain, unsigned int rgba)`: the color is packed as `r | g << 8 | b << 16 | a << 24` (`VNOISE_RGBA`), the op chain is `vnoise_chain_t { ops, n, data }`.
  - `vnoise_mask_blend(dst, w, h, before, before_stride, c0, r0, mask)`: the polygon pool moves into `vnoise_mask_t.data`.
  - `vnoise_plan_rivers(plan, const vnoise_rivers_out_t*)` and `vnoise_plan_fill(plan, c0, r0, w, h, detail, const vnoise_terrain_out_t*)`: output arrays in a struct.
- Every octave count (fractal, warp, cellular, damped, gullies) is clamped to `VNOISE_MAX_OCTAVES` (32), so a corrupted count cannot turn a fill into a multi-second loop.
- The Lua API (`fill_domain`, `fill_pipeline`, `fill_imagedata`, masks, `plan:rivers()`, `fill_terrain`) is unchanged and its outputs are bit-identical.
- `tests/abi.lua`: checks the binding's declarations, the octave bound, and that JIT-compiled calls match the interpreter.

## Capabilities

### New Capabilities
- `ffi-calling-convention`: register-only exported signatures and the octave bound.

### Modified Capabilities
- `noise-domain`: new `vnoise_fill_domain` signature.
- `noise-value-ops`: new image fill signatures (packed color, chain struct).
- `noise-pipeline`: `vnoise_mask_blend` reads the polygon pool from the mask.
- `terrain-detail`: `vnoise_plan_fill` takes its outputs in a struct.

## Impact

C API and the Lua binding's `cdef` (callers of `vnoise._lib` must update); Lua-level results unchanged. Consumer: Ludum (copies `libvnoise.dylib` and `lua/vnoise.lua`).
