## 1. C library

- [x] 1.1 Header: calling convention rule, `VNOISE_MAX_OCTAVES`, `VNOISE_RGBA`, `vnoise_chain_t`, `vnoise_rivers_out_t`, `vnoise_terrain_out_t`, `vnoise_mask_t.data`, `vnoise_sampler_t` before `vnoise_fill_domain`.
- [x] 1.2 New signatures in `domain.cpp`, `fill_imagedata.cpp`, `mask.cpp`, `terrain_plan.cpp`, `terrain_fill.cpp`.
- [x] 1.3 `clamp_octaves` in `fbm_sample`, `fbm_sample3`, `cellular_sample`, `damped_sample` and `vnoise_gullies`.

## 2. Binding

- [x] 2.1 `cdef` updated; `fill_domain`/`fill_pipeline` pass a sampler, `fill_imagedata` packs the color and the chain, `compile_mask` sets `mask.data`, `plan:rivers()` and `fill_terrain` pass output structs.

## 3. Verification

- [x] 3.1 Hashes of every affected output (domain fills, masked pipeline, mask source, image fills with and without ops, plan rivers, all `fill_terrain` outputs) identical before and after.
- [x] 3.2 `tests/abi.lua` added to `make test`; `tests/determinism.lua` uses the packed color; `make test` passes.
