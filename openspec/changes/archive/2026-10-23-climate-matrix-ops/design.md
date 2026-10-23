## Context

Matrix operations act on finite row-major matrices with values in 0..1 and measure heights in cells through `relief` (`relief * max(w, h)` cells for a value of 1). Flow accumulation (`matrix_network.cpp`) builds a depression-filled surface and D8 or MFD accumulation. Pipeline kernels (`kernels.cpp`) are exact but bounded by a 32-cell total radius.

## Decisions

- **Moisture as a steady upwind transport.** The moisture q at a cell is a function of q one step upwind, so the steady state is a fixed point solved in place. The upwind point is where the wind ray crosses the previous column (x-dominant wind) or row, linearly interpolated between two cells, a step of `L = 1 / max(|ux|, |uy|)` cells: no cell depends on itself (a bilinear sample one cell back would), and gains and rates scale with L so diagonal winds are not favored.
- **Gauss-Seidel sweeps by quadrant.** Each cell's two upwind neighbors lie one row and/or column back along its wind quadrant. In the sweep of a quadrant (rows and columns running with the wind) a cell of that quadrant reads neighbors already updated in the same sweep, so a uniform wind is exact after one cycle of four sweeps; winds that turn need more cycles (`iterations`, default 4, at most 256). Deterministic, no allocation beyond per-cell stencils.
- **Rates and gains are precomputed** per cell (neighbors, weight, step, gain, rate) since they depend only on the inputs; the sweeps only interpolate and update.
- **Rise measured above the sea.** Heights below `sea_level` count as `sea_level` in the rise, so the first land cell's rain depends on how high it stands above the sea, not on the depth of the seabed upwind.
- **Latitude bands without north.** Five row fractions (polar front, subtropical ridge, equator, ridge, polar front) give easterlies (trades, polar) toward -x and westerlies toward +x; the tilt turns easterlies toward the equator and westerlies toward the pole. Atmospheric circulation mirrors about the equator, so which edge is north does not change the winds; no orientation parameter is needed. Band edges are abrupt (zonal winds do not interact across rows).
- **Fetch.** Distance in cells along the wind since the last cell with source >= 0.5, carried by the same sweeps; an interpolation side without a source upwind is left out, and cells no source reaches read 1.
- **Normalization.** Precipitation by a fixed `range` or by the largest value; moisture by the capacity; fetch by `fetch_range` or the largest finite fetch.
- **Large blur: extended boxes (Gwosdek et al. 2011).** Each pass is a box of integer radius r with fractional end weights alpha chosen so the pass variance is exactly `sigma^2 / passes`; three passes are within about 1% of the value range of the exact Gaussian on fBm (more passes come closer). Prefix sums make each box O(1) per value. To match a clamped extension of the original matrix (as `apply_stages` pads), every line is extended by `passes * (r + 1) + 1` copies of its end values before the passes: clamping each intermediate pass instead would bend the result near the edges (several percent off at sigma 6). The extension costs O((w + h) sigma) per pass; sigma is capped at 16384.
- **Wetness index slope: steepest descent.** tan(beta) is the steepest drop to an 8-neighbor on the unfilled heights, the slope the water leaves by; a centered (Horn) gradient reads a sharp crest as flat and would give crests the index of a valley. Floored at `epsilon` (pits, flats). The area is the accumulation of the chosen method (MFD is the usual choice) per unit contour width of one cell. Normalized by `twi_range` or stretched over the matrix.
- **New entry point instead of a larger struct.** `vnoise_flow_twi` takes the new parameters and output by pointer (8 integer/pointer arguments, the limit), and `vnoise_flow` calls the same code without them, so `vnoise_flow_t` and `vnoise_flow_out_t` keep their layout.

## Costs (Apple M-series, 1024²)

Moisture with all outputs and 4 cycles ~35 ms; large blur ~16 ms at sigma 4 and ~50 ms at sigma 512; flow with the wetness index ~0.2 s (MFD).

## Risks

- Rates are per cell of the matrix being computed: the same map at another resolution needs scaled rates (`base_rate`, `evaporation`, `range`) to rain the same amounts; `relief` already keeps the orographic term scale-free.
- Precipitation normalized by its largest value depends on the whole matrix; previews of parts differ unless `range` is fixed.
