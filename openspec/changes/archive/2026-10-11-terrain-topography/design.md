## Context

vnoise is a C++17 shared library consumed through LuaJIT FFI. Its core contract: a cell's value depends only on its absolute index. Pipelines (domain, then point and kernel stages with an apron of at most 32 cells, then a final clamp to 0..1) preserve it, which is what lets Ludum stream its finite map (up to 16384 x 16384 cells) in 64 x 64 chunks.

A pipeline has exactly one fractal source. There is no cellular noise, no gradient information, and nothing that can see beyond the apron. Plausible terrain needs three things:
1. Several fields combined (continent, mountain belts, detail).
2. Slope-aware processes (erosion look).
3. Global hydrology: rivers that run downhill from source to mouth.

The first two are local. The third is not.

## Goals / Non-Goals

**Goals:**
- Plausible mountain systems, valleys and continuous rivers, with every output in 0..1.
- Keep absolute-index determinism for every block-level output, including plan outputs.
- An extensible base: a generic sampler struct, source trees, and a plan object with documented accessors, so that new terrain features (glaciers, sediment, biomes) can be added without new entry points each time.
- Remain fast enough for streaming: plan build once per world (hundreds of ms), block fills around 1 ms.

**Non-Goals:**
- Physically accurate hydraulic or thermal erosion at cell resolution (particle simulation). Cell-level erosion is faked with `gullies` and damped fBm.
- Infinite worlds with rivers. Rivers exist only inside the plan's finite extent.
- Changes to Ludum. Integration (recipes, Map Editor, water tiles) is a separate change in that repo.
- Multithreading.

## Decisions

### 1. Two-scale architecture: plan (global, coarse) + detail (local, by absolute cell)

```
 spec ──► sample height/uplift sources at macro nodes (Lua, fill_source)
          │
          ▼
 vnoise_plan_create (C++)
   repeat iterations: priority-flood ► D8 receivers ► stack order ► accumulation
                      ► implicit stream-power ► diffusion
   final: priority-flood ► routing ► accumulation ► lakes
   rivers: threshold ► chains ► polylines ► Chaikin ► width/bed ► running min
   index: bucket grid (macro_cell) ► segment ids
          │  immutable
          ▼
 vnoise_plan_fill(block) per chunk:
   Catmull-Rom (clamped) ► + headroom detail ► river query (warped) ► carve
   ► river / lake / flow / channel_distance
```

*Why:* global problems (drainage) are solved where they are cheap, on a coarse grid (257² nodes for the biggest Ludum map). Detail stays local, so chunks remain independent.

*Alternatives:*
- Purely local "river noise" (contours of `|n|`): continuous, but does not go downhill and has no sources or mouths.
- Full-resolution global simulation: 16384² is 268M cells, impossible to stream.
- Lazy tile-based hydrology with halo exchange: much harder to make deterministic and seam-free.

### 2. The plan takes buffers, the Lua side samples sources

`vnoise_plan_create` receives `height` and `uplift` as float arrays of `mw * mh`, not source descriptions. The source tree machinery (combinators, pipelines, seeds per leaf) lives in Lua, where pipelines already live. *Why:* the C core stays simple and testable with synthetic inputs (bowls, ramps), and any future source type works with plans automatically. *Alternative:* a C-side expression graph. That is more native speed, but the macro sampling is only about 66k points, so it is not worth it.

### 3. Erosion: implicit stream-power (Braun & Willett 2013) with per-iteration priority-flood

Implicit stream-power is unconditionally stable and O(n) per iteration given a topological order (built from receivers with an explicit stack, no recursion). Running priority-flood every iteration handles lakes simply (Cordonnier-style lake routing would be more accurate, but is more complex). The priority-flood uses a binary heap over nodes plus a plain FIFO queue for flat/pit cells, following Barnes et al. 2014 with the epsilon variant. Hillslope diffusion is explicit with a coefficient capped at 0.25 for stability.

Measured on 66k nodes (257²): re-flooding and re-routing every step cost about 5.8 ms per iteration (about 590 ms for 100 iterations). The drainage (flood, receivers, stack order, accumulation and the cached `A^m`) is therefore recomputed only every `erosion.reroute` steps (default 4). Drainage changes slowly between steps, and the implicit update stays stable. The build drops to about 190 ms for 100 iterations, including the macro sampling.

Defaults come from renders and a drainage metric (mean height of the top 5% accumulation nodes over the mean height): `k = 0.01` and `diffusion = 0.01`. With the initial `diffusion = 0.05`, smoothing erased the incision. Without uplift, long runs flatten the land, so mountain belts should also feed `uplift`.

Erosion can lower land under the sea level. The final drainage therefore recomputes the outlets from the eroded height. Otherwise rivers kept flowing through submerged lowland.

### 4. Keeping 0..1 without clipping artifacts

- Macro height: inputs are clamped to 0..1. Erosion only lowers, except for uplift. If the land max exceeds 1, the land part is rescaled linearly, so the sea level is preserved. Negatives are clamped (they can only appear through numerical noise).
- Interpolation: Catmull-Rom clamped to the local 2x2 node range never leaves the node range.
- Detail: `h + n * min(a, h, 1 - h)` with `|n| <= 1` is provably in [0, 1]. It squashes detail near the extremes instead of clipping, which also looks natural (flat sea floors and peaks).
- Carving: `b + (h - b) * s` with `0 <= b <= h` and `s` in [0, 1] stays within [b, h].
- Masks, distance and log-flow are normalized by construction.

No final clamp is needed, but the C fill still clamps defensively. That clamp has no effect in tests.

### 5. Rivers as vector polylines, carved per cell through a bucket index

Polylines (not a rasterized macro river mask) give sub-macro-cell geometry, width that varies with flow, smooth curves (Chaikin), and a natural API for the game (`plan:rivers()` for drawing, naming and bridges). The bed comes from the filled surface `F`, with depth growing as `sqrt(A)`, then a running minimum downstream. Tributaries are processed after their receiving river (descending order of flow at the junction), so the junction value is known. Each bucket (`macro_cell` cells) lists segment ids whose capsule overlaps it. With a typical river density, each bucket holds a handful of segments, so the query cost is bounded and independent of the network size.

Meanders displace the *query point* with a bounded warp, instead of moving the polylines. This keeps the river continuous, deterministic and cheap, and the bed function along the warped channel is still the polyline's. *Alternative:* perturbing polyline vertices (a sine offset or noise) at build time. Rejected because it can create self-intersections and needs re-indexing. It may come later as `rivers.wiggle`.

### 6. Generic sampler struct for new modes

`vnoise_sampler_t` (mode, base, octaves, lac, gain, jitter, damping, and 4 reserved floats) plus a single `vnoise_fill_sampler`. Existing functions are untouched (`vnoise_fill_domain` becomes a thin wrapper internally, so modes 0..2 stay bit-identical). New modes no longer change function signatures. *Alternative:* one `*_fill_*` function per new noise. Rejected because the header would multiply.

### 7. Cellular noise

A 2D jittered lattice, with feature points hashed from the seed. The search covers the 5x5 neighborhood without its corners (exact for jitter <= 1, both F1 and F2), using an early-exit order by cell distance. Normalization constants are fixed (F1/1, F2/1.5, edge/1), and the result is clamped to 0..1. That is simple and documented, rather than a statistical normalization that would vary.

### 8. Damped fBm and gullies need gradients

`simplex2_deriv` and `perlin2_deriv` return analytic gradients (simplex: sum of each corner's `-8 t^3 (g·d) d + t^4 g` terms; Perlin: product rule with the quintic fade derivative). Damped fBm follows Quilez' "fbm with derivatives".

`gullies` is a stage, not a sampler mode, so it can erode *anything*: a plan output, a source tree, a curve. It takes the input gradient by central differences (radius 1), and the stripe field is analytic in absolute coordinates (jittered lattice points from the seed and octave), so it is block-independent. It is in the spirit of the "erosion noise/filter" technique (clayjohn; Rune Skovbo Johansen 2023).

Kernel stage `run` gets two new arguments, `(c0, r0, state)`. Existing stages ignore them.

### 9. Source trees in Lua, combinators in C

Combinator nodes allocate one buffer per child of the node's size and combine with a small exported C helper (`vnoise_combine(dst, src, count, op, weight)`), which avoids Lua loops over cells. Pipeline leaves and plan leaves fill their buffers through their own paths. Compilation validates the tree once. Buffer scratch is reused per compile when sizes match, to limit allocations in streaming.

### 10. Plan lifetime and FFI

The plan is an opaque C handle. Lua wraps it in a table with an `ffi.gc(handle, lib.vnoise_plan_destroy)` and caches Lua-side copies of the river list on first `rivers()` call. Accessors read the macro grids (`vnoise_plan_grid(plan, which, out)`) and the river arrays (counts plus flat arrays).

## Risks / Trade-offs

- [Macro resolution limits river detail: rivers follow 64-cell steps] → Chaikin smoothing, meander warp and `macro_cell` configurable down to 4 (a 4096 map at 16 gives 257² nodes).
- [Build time over budget with many iterations] → iterations is configurable; tests report timing; optional flood-every-k as follow-up.
- [Carving creates visible "valley capsules" with straight edges at macro segments] → valley half-width grows with flow, smoothstep profile, Chaikin passes, and the detail damping blends the edges.
- [Cellular normalization constants clip rare values with jitter 1] → documented. The clip is rare and only at extreme distances.
- [Lake rendering] → lakes are a mask plus surface. The terrain under a lake keeps its eroded bottom. Consumers decide how to draw water.
- [`-ffast-math` and determinism across machines] → determinism is promised per build, as for the existing library. Tests compare within tolerances, except the plan determinism test, which compares on the same build.
- [API surface grows a lot in one change] → grouped as separate capabilities. Each piece is testable alone (cellular, damped, gullies, sources, plan, detail).

## Migration Plan

Additive only. Existing outputs were checked bit for bit against the previous library: a legacy pipeline with every kernel family, `fill_domain`, `fill_grid` with ops and `fill_white` give identical values. The LÖVE preview is a separate example (`examples/terrain`), so the existing demo is untouched. After pushing to vg-noise main, Ludum gets the new library and binding with `make build-noise` when it is ready to integrate. Nothing breaks if it does not. Rollback means reverting the commit.

## Open Questions

- Should the plan also export a coarse "moisture" output (distance to water, weighted by flow) for biomes? That is deferred and easy to add as another output.
- ~~Is flood-every-k iterations needed for performance?~~ Yes: resolved with `erosion.reroute` (default 4); see decision 3.
- Should the meander warp also shift the valley sides (it does, since the query is warped) or only the channel? The current choice is both, for coherence.
