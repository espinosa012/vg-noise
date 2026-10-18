## 1. Domain warp

- [x] 1.1 `warp_levels`, `warp_lac`, `warp_gain` in `vnoise_domain_t` (header and binding); shared `warp_point` in `domain.cpp` used by `vnoise_fill_domain` and `domain_point`; bit-identity of one level checked against the previous library.
- [x] 1.2 Lua `compile_domain` reads `warp.levels` (1..4, else an error), `warp.lac`, `warp.gain`.

## 2. Matrix operations

- [x] 2.1 `vnoise_warp_matrix`, `vnoise_warp_matrix_noise`, `vnoise_distance_field`, `vnoise_slope` (`cpp/src/matrix_analysis.cpp`).
- [x] 2.2 `vnoise_erode_hydraulic`, `vnoise_erode_thermal` (`cpp/src/matrix_erosion.cpp`).
- [x] 2.3 `vnoise_flow`, `vnoise_river_network` (`cpp/src/matrix_network.cpp`) over the shared hydrology.
- [x] 2.4 Header declarations with comments; Lua wrappers `vnoise.warp`, `vnoise.erode_hydraulic`, `vnoise.erode_thermal`, `vnoise.distance_field`, `vnoise.slope`, `vnoise.flow`, `vnoise.river_network`.

## 3. Tests and docs

- [x] 3.1 `tests/landforms.lua` with every scenario and 1024² timings; added to `make test`; `tests/abi.lua` passes.
- [x] 3.2 README section "Landform operations"; LDoc docstrings.
- [x] 3.3 Validate, archive and sync the specs; push and merge.
