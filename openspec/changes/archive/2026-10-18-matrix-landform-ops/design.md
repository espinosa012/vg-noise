## Context

The library already has the hydrology of terrain plans (`hydrology.{h,cpp}`: outlets, priority-flood, D8 routing, stack order), a single-river tracer with carving (`matrix_rivers.cpp`) and the domain warp of sampler fills (`domain.cpp`). The new operations act on finite row-major matrices with values in 0..1, like the other matrix operations.

## Decisions

- **Heights in cells (`relief`).** Droplet physics, talus angles and slopes need heights and distances in the same unit. A value of 1 stands `relief * max(w, h)` cells high; since that scales with the resolution, a slope keeps its angle when the same map is computed at another resolution (the editor previews at a lower one). Default 0.05.
- **Untouched cells keep their exact value.** Erosion works on scaled heights; a cell is written back as `value + change / scale` only if its scaled height changed, so flat areas and hard rock are bit-identical (with `-ffast-math`, `v * Z / Z` is not).
- **Droplets keep the material.** A droplet that leaves the matrix or dries out drops its load where it is, and one that reaches the sea drops it there (deltas). Material is conserved within about 2% (the final clamp and the brush clipping at 0).
- **Thermal erosion is synchronous** (a delta buffer per pass): the result does not depend on the scan order. Each cell moves `rate` times half its steepest excess drop, shared by the steep neighbors in proportion to their excess, which never reverses a slope.
- **Distance: Felzenszwalb-Huttenlocher.** Exact, separable, linear in the cells, unbounded (unlike the `distance` kernel). Edge modes pad the matrix by one cell on the chosen side. Signed distances put the boundary half a cell from the cells on each side, so the coast line itself is 0.5.
- **Warp reuses the domain.** The noise warp of a matrix builds an identity `vnoise_domain_t` and calls `domain_point`, so a matrix warp displaces cell `(i, j)` exactly as a sampler fill would. Iterated levels sample the field at the point displaced by the previous level with level-specific offsets; level 0 keeps the original offsets, so one level is the old warp, bit for bit.
- **River network over the D8 drainage.** Channels are cells with accumulated rain `>= min_flow` above the sea; a channel's receiver has more flow, so it is a channel too (or the sea, or an edge outlet). Rivers are built from the unassigned channel cell with most flow upstream along the donor with most flow: main stems first, and every later river ends at a cell of an earlier one, whose bed is known, so tributaries join at the stem's bed. The profile uses the depression-filled surface, so a river crosses a lake at its surface instead of digging a trench through the sill. All segments go into one bucket index and every cell is carved by its nearest segment in a single pass (cost independent of the number of rivers). Carving and the mask follow `vnoise_river`.
- **Struct pointers for every parameter set**, so no function passes more than 8 integer/pointer or 8 float arguments.

## Costs (Apple M-series, 1024²)

Warp (two levels) ~150 ms; hydraulic erosion (0.3 droplets per cell) ~0.3 s; thermal (50 passes) ~0.5 s; signed distance ~27 ms (2048²: ~0.17 s); slope ~5 ms; flow D8 ~0.1 s, MFD ~0.2 s; river network ~0.12 s.

## Risks

- Hydraulic results depend on the droplet count, which the Lua wrapper derives from a density per cell; at another resolution the gullies differ in detail, not in character.
- `vnoise_domain_t` grows: a binding older than the library would pass a shorter struct. Ludum copies both together.
