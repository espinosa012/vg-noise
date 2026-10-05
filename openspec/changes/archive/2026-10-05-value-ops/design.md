## Context

vg-noise evaluates fractal noise in C and exposes fills (`*_fill_grid`, `*_fill_imagedata_rgba8`) through a LuaJIT FFI binding. The image fill already does one post-process step (linear `lo`/`hi` map plus clamp). The ludum map editor now needs user-defined chains of value operations (scale, offset, contrast, more later), applied identically in its image preview and in its in-game grid sampling.

## Goals / Non-Goals

**Goals:**
- One C implementation of value ops, shared by single-value, buffer and fused image paths.
- An op encoding that admits future ops without new entry points.
- No ABI or output change for existing callers.

**Non-Goals:**
- Non-pointwise ops (blur, erosion, neighbourhood filters).
- 3D volume variants (can map a filled volume with `vnoise_map_buffer`).
- Ops with array parameters (curves); a later change can add a separate entry point.

## Decisions

- **Op encoding `{ int op; float p[4]; }`.** Fixed-size, POD, trivially built from LuaJIT (`ffi.new("vnoise_op_t[?]", n)`). Four params cover every planned pointwise op (remap with in/out ranges, terraces, pow, smoothstep). Alternative: one entry point per op (rejected: combinatorial with fills, and chains need order).
- **Interpreted chain with a `switch` per value.** Chains are short (≤ ~8); the branch is predictable because every value runs the same sequence. Cost is small next to multi-octave noise evaluation. Alternative: JIT-like specialization (rejected: complexity).
- **Single final clamp.** Ops compose on unclamped values; the only clamp is the final optional one, so saturation never loses information between steps. Callers that want normalized-then-clamped behavior put `remap` first.
- **New `_ops` image variants instead of changing the existing ones.** Keeps the existing symbols bit-identical. The ops variant drops `lo`/`hi`; callers express them as a leading `remap`. The Lua binding hides this: `fill_imagedata` with `opts.ops` prepends `remap(lo, hi)`.
- **Grid ops as a second pass (`vnoise_map_buffer`).** `fill_grid` is used for numeric grids where an extra linear pass is negligible, and avoids three more grid variants.
- **`compile_ops` for reuse.** Building the cdata array per call allocates; callers that refill often (an editor preview) compile once and pass the compiled chain. Accepting plain lists too keeps simple uses simple.
- **Remap with zero range returns 0** instead of producing inf/NaN under `-ffast-math`.

## Risks / Trade-offs

- [`-ffast-math` reorders float math] → results may differ in the last ulp from a Lua reference; tests compare with a tolerance (1e-5), except the fused-vs-existing image test, which compares bytes produced by the same arithmetic path.
- [Unknown op ids silently pass through in C] → the Lua binding validates names, so only raw C callers can hit it; documented.
- [`p[4]` too small for a future op] → that op gets its own entry point; the chain format is unaffected.
