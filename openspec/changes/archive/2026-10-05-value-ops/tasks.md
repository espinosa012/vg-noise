## 1. C API

- [x] 1.1 Add `vnoise_op_t`, `VNOISE_OP_*` ids and the declarations of `vnoise_apply_ops`, `vnoise_map_buffer` and the three `*_fill_imagedata_ops_rgba8` functions to `cpp/include/vnoise/vnoise.h`
- [x] 1.2 Add an inline `apply_ops` helper in `cpp/include/vnoise/internal.h` (switch per op, no intermediate clamp, remap with zero range returns 0)
- [x] 1.3 Implement `vnoise_apply_ops` and `vnoise_map_buffer` in new `cpp/src/value_ops.cpp` (NULL/zero-count guards)
- [x] 1.4 Add the `_ops` image fill macro and its three instances in `cpp/src/fill_imagedata.cpp`, writing pixels exactly like the existing fill

## 2. Lua binding

- [x] 2.1 Add the new cdefs and `OP_*` constants to `lua/vnoise.lua`
- [x] 2.2 Implement `vnoise.compile_ops(list)` (names or ids, error on unknown name) and `vnoise.apply_ops(v, ops, clamp)`
- [x] 2.3 Support `opts.ops`/`opts.clamp` in `fill_grid` (map after fill) and `opts.ops` in `fill_imagedata` (prepend `remap(lo, hi)`, call the `_ops` variant)

## 3. Tests and docs

- [x] 3.1 Add `tests/value_ops.lua` covering every scenario of the `noise-value-ops` spec, run with LuaJIT against the built library
- [x] 3.2 Run the existing smoke and determinism tests to confirm unchanged output
- [x] 3.3 Document ops in `README.md` (C API and Lua usage)
- [x] 3.4 Push to `main`; in ludum, `make build-noise` copies the dylib and binding
