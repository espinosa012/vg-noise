## ADDED Requirements

### Requirement: Generic sampler description
The library SHALL export `vnoise_sampler_t { int mode; int base; int octaves; float lac, gain; float jitter; float damping; float p[4]; }` and `void vnoise_fill_sampler(const noise_state_t* s, const vnoise_sampler_t* sp, float* out, int c0, int r0, int w, int h, const vnoise_domain_t* d)`. For every cell `(c0 + i, r0 + j)` it SHALL write `out[j * w + i]`, the sampler evaluated at the point the domain `d` maps the cell to (the same mapping as `vnoise_fill_domain`). The modes SHALL be `VNOISE_MODE_FBM` (0), `VNOISE_MODE_RIDGE` (1), `VNOISE_MODE_TURB` (2), `VNOISE_MODE_CELL_F1` (3), `VNOISE_MODE_CELL_F2` (4), `VNOISE_MODE_CELL_EDGE` (5), `VNOISE_MODE_CELL_VALUE` (6) and `VNOISE_MODE_DAMPED` (7). `p` is reserved for future modes and SHALL be ignored by these. The function SHALL do nothing for NULL pointers, non-positive sizes or an unknown mode. A cell's value SHALL depend only on its absolute index and the other arguments.

#### Scenario: Fractal modes match the domain fill
- **WHEN** `vnoise_fill_sampler` runs with mode 0, 1 or 2 and the same base, octaves, lacunarity, gain and domain as a `vnoise_fill_domain` call
- **THEN** both buffers agree within 1e-6

#### Scenario: Unknown mode
- **WHEN** the mode is 99
- **THEN** the output buffer is left untouched

### Requirement: Sampler in Lua
The Lua binding SHALL provide `vnoise.fill_sampler(state, spec, opts)`. `spec` is `{ kind = "fbm" | "ridge" | "turb" | "cell_f1" | "cell_f2" | "cell_edge" | "cell_value" | "damped", base, octaves, lac, gain, jitter, damping }`, and `opts` holds `c0`, `r0`, `w`, `h`, `freq`, `ox`, `oy`, `domain`, `out`. It SHALL return the `float[w * h]` buffer and raise an error naming an unknown kind. Defaults SHALL be base simplex 2D, 6 octaves, lacunarity 2, gain 0.5, jitter 1, damping 1.

#### Scenario: Unknown kind
- **WHEN** `fill_sampler` is called with `kind = "voronoi3"`
- **THEN** it raises an error that names `voronoi3`

### Requirement: Analytic 2D gradients
The library SHALL export `float simplex2_deriv(const noise_state_t* s, float x, float y, float* dx, float* dy)` and `float perlin2_deriv(...)` with the same signature. Each SHALL return the same value as `simplex2_eval`/`perlin2_eval` and write the analytic partial derivatives to `dx` and `dy` when they are not NULL.

#### Scenario: Gradient matches finite differences
- **WHEN** the derivatives are evaluated at 1000 random points and compared with central differences of step 1e-3
- **THEN** every component agrees within 1e-2 and the returned values equal the plain evaluation within 1e-6

### Requirement: Derivative-damped fBm
The `VNOISE_MODE_DAMPED` mode SHALL sum octaves like fBm, using base Perlin 2D or Simplex 2D (any other base SHALL fall back to Simplex 2D). Each octave adds `a * n / (1 + damping * |D|^2)`, where `n` is the octave's noise, `a` its amplitude, and `D` the running sum of `a * gradient` over the octaves so far, this one included. Each gradient is taken with respect to the octave's own input coordinates. The sum SHALL be divided by the sum of amplitudes, so values stay in about [-1, 1]. With `damping = 0` the result SHALL equal fBm.

#### Scenario: No damping equals fBm
- **WHEN** a block is filled in mode damped with `damping = 0` and in mode fBm with the same parameters
- **THEN** the two agree within 1e-5

#### Scenario: Damping smooths steep areas
- **WHEN** a 256 x 256 block is filled with `damping = 0` and with `damping = 4`
- **THEN** the mean absolute difference between neighboring cells is lower with `damping = 4`

### Requirement: Gullies erosion filter stage
Pipelines SHALL accept a kernel stage `{ "gullies", scale = s, strength = k, octaves = o, gain = g, sharpness = p }`, where `s` (default 8) is the gully spacing in cells (> 0), `k` (default 0.05) is the strength in value units, `o` (1..4, default 2) is the octave count, `g` (default 0.5) is the per-octave strength factor, and `p` (default 1) controls the slope response. The stage's radius SHALL be 1. For each output cell it SHALL take the input gradient `G` by central differences. If `|G|` is 0, the cell keeps its input value. Otherwise it SHALL add `k * min(1, p * |G| * s) * gully(c, r)`. Here `gully` sums, over `o` octaves of spacing `s / 2^i` and weight `g^i`, a weighted average of `cos(2π * dot(q - x, Gp) / spacing)`. `q` ranges over the feature points of the octave's cell lattice around the cell (one per lattice cell, jittered within the central half of the cell), `x` is the cell position, and `Gp` is the unit vector perpendicular to `G`, so the stripes run down the slope. The feature points SHALL come from the pipeline state's seed and the octave index. The weights SHALL be `(1 - (dist / 1.25)^2)^2`, with the distance in lattice cells, so they fall smoothly to 0 at 1.25 lattice cells. Octaves are averaged with weights `g^i`, so `gully` lies in [-1, 1]. The result SHALL depend only on absolute cell indices.

#### Scenario: Flat input is unchanged
- **WHEN** `gullies` runs on a constant 0.4 block
- **THEN** every output value is 0.4

#### Scenario: Gullies tile
- **WHEN** a pipeline of `damped` noise followed by `gullies` fills 64 x 64 cells, and again as four 32 x 32 blocks
- **THEN** every cell agrees within 1e-5

#### Scenario: Bad parameter
- **WHEN** a `gullies` stage has `scale = 0` or `octaves = 5`
- **THEN** `compile_pipeline` raises an error naming the parameter
