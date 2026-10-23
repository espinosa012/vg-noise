## Why

Ludum's Map Editor builds a world's climate (precipitation, humidity, temperature) from world matrices to classify biomes. The landform operations give heights, slopes, flow and rivers, but three pieces are missing:

- **Precipitation that follows the wind and the relief.** Humidity from noise or from the distance to the coast ignores where the wind comes from: windward mountain slopes should be wet and their lee a rain shadow, and the air should dry out the farther it travels over land.
- **Blurs at continental scale.** Climate fields are smooth over hundreds of cells (continentality, softened rain bands). The pipeline `gaussian` stage is exact but bounded by the 32-cell total kernel radius and costs O(sigma) per cell.
- **Soil wetness from the topography.** The flow accumulation is there; the topographic wetness index (`ln(a / tan(beta))`) that combines it with the slope is the standard proxy for wet valley floors and dry ridges.

## What Changes

- `vnoise_moisture` (`vnoise_moisture_t`, `vnoise_moisture_out_t`): moisture carried by the wind over a height matrix, picked up over the sources (a source matrix, or the cells below `sea_level`), rained out over land at a base rate plus an orographic term proportional to the height climbed in cells (`relief`). Wind from a direction matrix or from latitude bands by row (trade winds, westerlies, polar easterlies, optional tilt). Outputs: precipitation, moisture carried, fetch (distance along the wind since the last source). Lua `vnoise.moisture`.
- `vnoise_blur_matrix` (`vnoise_blur_t`): Gaussian blur of any sigma as successive extended box filters (exact variance), O(1) per cell, clamped edges. Lua `vnoise.blur_large`.
- `vnoise_flow_twi` (`vnoise_twi_t`): `vnoise_flow` plus the topographic wetness index of the same accumulation; Lua `vnoise.flow` returns it as a fourth value with `twi = true`. `vnoise_flow` itself is unchanged.
- Tests (`tests/climate.lua`, in `make test`; `tests/abi.lua` calls the new functions hot), README section "Climate operations", header comments.

## Capabilities

### New Capabilities
- `matrix-climate`: moisture transport with orographic precipitation, and large Gaussian blurs of a matrix.

### Modified Capabilities
- `matrix-analysis`: flow accumulation also yields the topographic wetness index.

## Impact

New `cpp/src/matrix_climate.cpp`; `matrix_filters.cpp` (blur), `matrix_network.cpp` (wetness index), `vnoise.h`, `lua/vnoise.lua`. No existing struct or signature changes, so a binding and library of different versions still agree on every existing function. Every new function respects the register-only argument rule (`tests/abi.lua`).
