## 1. Operations

- [x] 1.1 `vnoise_moisture` with `vnoise_moisture_t` and `vnoise_moisture_out_t` (`cpp/src/matrix_climate.cpp`): stencils, band winds, quadrant sweeps, precipitation, moisture and fetch outputs.
- [x] 1.2 `vnoise_blur_matrix` with `vnoise_blur_t` (`cpp/src/matrix_filters.cpp`): extended boxes with exact variance over clamped, extended lines.
- [x] 1.3 `vnoise_flow_twi` with `vnoise_twi_t` (`cpp/src/matrix_network.cpp`); `vnoise_flow` shares its code and is unchanged.
- [x] 1.4 Header declarations with comments; Lua `vnoise.moisture`, `vnoise.blur_large` and `vnoise.flow` with `twi`, validating their specs.

## 2. Tests and docs

- [x] 2.1 `tests/climate.lua` with every scenario and 1024² timings; added to `make test`; `tests/abi.lua` calls the new functions from JIT-compiled code.
- [x] 2.2 README section "Climate operations"; LDoc docstrings.
- [x] 2.3 Validate, archive and sync the specs; push.
