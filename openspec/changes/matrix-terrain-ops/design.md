## Context

vg-noise evaluates infinite fields per block by absolute cell (samplers, pipelines, source trees) and builds finite-world terrain plans automatically. Map authoring needs explicit, positioned edits on a finite elevation matrix: the author decides where mountains, features and rivers go. Each edit reads the current matrix, so edits compose as a sequence. The consumer (Ludum's Map Editor) keeps a list of steps. It re-runs them from the first changed step, and stores the results so a map can be replicated.

## Goals / Non-Goals

**Goals:**
- Positioned operations on a `float[w * h]` matrix: stamps, path features, rivers, erosion, existing stages, resampling.
- Values always in 0..1; deterministic for equal inputs, parameters and seeds.
- Fast enough for interactive editing at working resolutions up to 2048²: stamps and paths in a few ms, a river in a few ms, erosion in hundreds of ms.
- Share the hydrology code with the terrain plan instead of duplicating it.

**Non-Goals:**
- Tiling. Matrix operations are global on purpose; chunk tiling stays the job of samplers and pipelines.
- Undo history. That belongs to the consumer, which replays steps.
- Biomes, water simulation, river polyline editing.

## Decisions

### 1. Plain buffers and explicit sizes

Every C function takes `float* buf, int w, int h`, plus a parameter struct with a `seed` where randomness is involved. Positions are in matrix cells (float, the cell center is `i + 0.5`). Lengths are in cells. Callers that work in normalized coordinates convert. Results are clamped to 0..1 once, at the end of each operation.

*Why:* this matches the existing kernels (plain buffers, no hidden state), and a consumer can cache any intermediate matrix.

### 2. Stamps: profile × footprint, blended

A stamp computes, for each cell inside its bounding box:
- `d`: the normalized elliptical distance. The point is rotated by `angle`, then divided by `(rx, ry)`. The outline is perturbed by seeded fBm over the polar angle, with amplitude `roughness * 0.25`.
- A profile `p(d)` per shape, in 0..1:
  - `dome`: `(1 - d²)²`;
  - `cone`: `1 - d`, minus a crater dip of radius `crater` (fraction of the radius) when given;
  - `crater`: a rim peak at `d = 1 - rim` and a floor at `floor_height`;
  - `mesa`: 1 up to `1 - slope`, then a smoothstep down to 0;
  - `basin`: the dome profile with a negative sign.
- A surface roughness `p *= 1 + roughness * 0.3 * fbm`.

The value `v = height * p` is blended into the matrix:

| Blend | Result |
|---|---|
| `add` | `m + v` |
| `sub` | `m - v` |
| `max` | `max(m, v)` |
| `min` | `min(m, v)` |
| `replace` | `m + w * (target - m)`, with `w = p` the footprint weight and `target = height` |

Only the bounding box is visited, so the cost is proportional to the stamp's area.

### 3. Path features: distance to a smoothed polyline

The points are smoothed with Chaikin (`smooth` passes, ends kept). For each cell in the path's bounding box grown by the width, the operation finds:
- the distance `d` to the nearest segment;
- the arc-length parameter `t` in 0..1 along the path;
- the side of the line (the sign of the cross product).

A spatial bucket grid over the segments keeps this linear in the area. Then:
- **`ridge`**:
  - envelope `e(t) = smoothstep(0, taper, t) * smoothstep(0, taper, 1 - t)`;
  - cross profile `c = (1 - (d / half_width)²)₊^sharpness`;
  - peaks `k = mix(1, ridged_fbm(seed, along/across), peakiness)`.

  Its value is `height * e * c * k`. Spurs come from a domain warp of `d` by fBm (`spurs` amplitude), which makes the flanks branch.
- **`valley`**: `depth * e * c`, subtracted from the matrix.
- **`escarpment`**: on the raised side, `height * e * smoothstep(0, width, d)`; the other side is unchanged.

Blends work as for stamps.

### 4. Rivers: steepest descent with local breaching

`vnoise_river(height, w, h, sx, sy, params, mask, out_points, max_points)`:
1. Start at the source cell and repeatedly move to the 8-neighbor with the steepest descent.
2. At a pit, run a bounded priority-flood from the pit (`breach_radius` cells, default 64), until it reaches a cell lower than the pit. Follow the flood's back-pointers from that cell (the spill path), then carve the cells along it so they never rise. If the flood exceeds its radius, the river ends in a lake: the filled cells are written to the mask as lake, with value 0.5.
3. Stop at a cell `< sea_level`, at the matrix edge, or at a cell whose mask is ≥ 0.75 (an existing river: a junction).
4. Smooth the path (Chaikin).
5. Make the bed non-increasing. The bed is the smoothed path heights minus a depth that grows with distance: `depth = depth0 + depth_growth * length`, capped. Then take a running minimum. At a junction, the bed meets the existing channel's height at that point.
6. Carve: for cells within `width(t) / 2 + bank` of the path, `h = min(h, bed + (h - bed) * s ^ valley_shape)`, with `s = smoothstep(w/2, w/2 + valley, d)`. Write `mask = max(mask, channel weight)`.
7. Return the number of polyline points.

Every write is clamped to 0..1.

`vnoise_river_sources(height, w, h, count, min_elev, min_spacing, seed, out_xy)`: seeded candidate draws weighted by `(h - min_elev)₊`, rejecting candidates closer than `min_spacing` to an accepted one, until `count` are found or a fixed attempt budget runs out. Returns how many were found.

### 5. Erosion on a matrix reuses the plan

The hydrology internals move from `terrain_plan.cpp` to `hydrology.{h,cpp}`:
- `Grid`, priority-flood, routing, stack order, accumulation, the stream-power step, diffusion, Chaikin.

`vnoise_erode_matrix(h, w, h_, params, flow_out)` runs `iterations` steps with `reroute`, `k`, `m`, `dt`, `diffusion` and an optional uplift matrix, and writes the eroded heights. Above 1M cells, it erodes a bilinear downsample (to at most 1M cells), then adds the upsampled height change to the original. That keeps the detail, and the time stays bounded. It can also write the log-normalized flow accumulation, in 0..1, to `flow_out`. The plan's results must stay bit-identical after the move: its tests and a dump comparison check that.

### 6. Stages on a matrix

`vnoise.apply_stages(buf, w, h, stages)` compiles a pipeline with no source and runs its stages on a padded copy: the matrix is extended by the pipeline radius with clamped edges. Masks use matrix cells. The result is clamped. This reuses every kernel and point op, in the same native code as `fill_pipeline`.

### 7. Resampling

`vnoise_resample(src, sw, sh, dst, dw, dh, mode)` maps cell centers (`(i + 0.5) * sw / dw - 0.5`) in bilinear or bicubic Catmull-Rom mode. The bicubic result is clamped to the 2 x 2 neighborhood, so it never overshoots. Values stay in 0..1.

## Risks / Trade-offs

- [Breaching large flat areas is slow] → The local flood is bounded by `breach_radius`; past it, the river becomes a lake.
- [Rivers drawn by hand can cross ridges if the matrix is edited after the river step] → In the consumer, rivers are steps that re-run after earlier steps change.
- [Erosion at a reduced resolution loses fine erosion detail on large matrices] → Documented. Interactive editing works at preview resolutions anyway.
- [Moving the hydrology code could change the plan's outputs] → The plan's outputs are dumped before the move and compared bitwise after it.

## Migration Plan

Additive. Move the hydrology code first and verify the plan's bit-identity. Then add the operations, tests, docs and example, and push to `main`.

## Open Questions

- Rivers with tributaries generated automatically from one source: no for now. Multiple sources plus junctions cover it.
