## 1. Point ops

- [x] 1.1 Add `VNOISE_OP_INVERT` .. `VNOISE_OP_CLAMP` to `vnoise.h` and `apply_ops`
- [x] 1.2 Op names and constants in `lua/vnoise.lua`

## 2. Domain

- [x] 2.1 `vnoise_domain_t` and `vnoise_fill_domain` (new `cpp/src/domain.cpp`)
- [x] 2.2 `vnoise.compile_domain` (affine from rotate/scale/flip/translate/pivot, warp)

## 3. Kernels

- [x] 3.1 `vnoise_convolve`, `vnoise_convolve_sep`, `vnoise_sobel` (new `cpp/src/kernels.cpp`)
- [x] 3.2 `vnoise_morph`, `vnoise_morph_radius`, `vnoise_median`, `vnoise_distance`

## 4. Masks and pipeline

- [x] 4.1 `vnoise_mask_t`, `vnoise_mask_blend` (new `cpp/src/mask.cpp`)
- [x] 4.2 `vnoise.compile_pipeline` (stages, presets, masks, radius limits)
- [x] 4.3 `vnoise.fill_pipeline` (apron, ping-pong buffers, grouped point ops, masked stages, final clamp)
- [x] 4.4 `vnoise.histogram`, `vnoise.otsu`, `vnoise.equalize_lut`

## 5. Tests and docs

- [x] 5.1 `tests/image_ops.lua` covering every scenario; `make test` runs it
- [x] 5.2 Existing tests unchanged
- [x] 5.3 README sections (point ops, domain, kernels, pipeline, masks, statistics)
- [x] 5.4 Push to `main`; rebuild in ludum with `make build-noise`
