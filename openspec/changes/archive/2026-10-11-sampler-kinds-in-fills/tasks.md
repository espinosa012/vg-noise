## 1. Binding

- [x] 1.1 Move the sampler kind table and `samplerStruct` above the fill functions; add `fillSampler(kind, opts)` (nil for classic kinds).
- [x] 1.2 `fill_grid`, `fill_domain`, `fill_pipeline`: use `vnoise_fill_sampler` for the new kinds; `modeOf` accepts every kind.
- [x] 1.3 Docstrings and README.

## 2. Verification

- [x] 2.1 Tests in `tests/terrain.lua` (equality with `fill_sampler`, jitter, unknown kind, tiling); `make test` passes, legacy image-op tests unchanged.
