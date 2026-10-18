# noise-domain Specification

## Purpose
Define absolute-cell sampling through a domain transform (affine map in cell space plus optional fBm warping), so that rotation, scaling, mirroring and translation are exact and every cell depends only on its absolute index.

## Requirements

### Requirement: Absolute cell sampling with a domain transform
The library SHALL export `void vnoise_fill_domain(const noise_state_t* s, const vnoise_sampler_t* sp, float* out, int c0, int r0, int w, int h, const vnoise_domain_t* d)`, which reads `mode`, `base`, `octaves`, `lac` and `gain` from `sp`, with `vnoise_domain_t { float m[6]; float ox, oy, freq; float warp_amp, warp_freq; int warp_octaves; int warp_base; int warp_levels; float warp_lac, warp_gain; }`. For every `0 <= i < w`, `0 <= j < h`, with `c = c0 + i`, `r = r0 + j`, it SHALL set `out[j * w + i]` to the fractal sample (`mode` 0 fBm, 1 ridge, 2 turbulence) at `(ox + c'' * freq, oy + r'' * freq)`, where `(c', r') = (m0 c + m1 r + m2, m3 c + m4 r + m5)` and `(c'', r'')` is `(c', r')` displaced by `warp_amp` times two fBm samples of the warp field at `(c' * warp_freq + 5.2, r' * warp_freq + 1.3)` and `(c' * warp_freq + 1.7, r' * warp_freq + 9.2)` when `warp_amp != 0` (`warp_octaves` octaves, lacunarity `warp_lac` and gain `warp_gain`, 0 meaning 2 and 0.5, base `warp_base`). With `warp_levels` from 2 to 4 (`VNOISE_MAX_WARP_LEVELS`; smaller values mean 1, larger ones 4) the warp SHALL be iterated: level k samples the warp field at the point displaced by level k - 1, with its own offsets, and the last level's displacement is applied; one level SHALL be bit-identical to the warp without these fields. It SHALL do nothing for NULL pointers, non-positive sizes or a mode other than 0, 1 and 2. A cell's value SHALL depend only on its absolute index and the arguments other than `c0`, `r0`, `w`, `h`.

#### Scenario: Identity matches the grid fill
- **WHEN** `vnoise_fill_domain` runs with the identity affine, no warp and origin `(ox, oy)` over cells from `(c0, r0)`
- **THEN** every value equals `fill_grid` with origin `(ox + c0 * freq, oy + r0 * freq)` within 1e-5

#### Scenario: Overlapping blocks agree
- **WHEN** a 40 x 40 block from `(0, 0)` and a 20 x 20 block from `(17, 9)` are filled with the same rotated and warped domain
- **THEN** the shared cells have the same values within 1e-5

#### Scenario: Iterated warp
- **WHEN** a block is filled with `warp_levels` 1 and default lacunarity and gain, and another with 2 levels
- **THEN** the first equals the fill of the previous library bit for bit, and the second differs; overlapping blocks with 3 levels agree within 1e-5

### Requirement: Domain description in Lua
The Lua binding SHALL provide `vnoise.compile_domain(spec)` returning a `vnoise_domain_t` from `{ rotate = degrees, scale = s | {sx, sy}, flip_x, flip_y, translate = {tx, ty}, pivot = {px, py}, warp = { amp, freq, octaves, base, levels, lac, gain } }` (all optional) as the inverse map `c' = pivot + M (c - translate - pivot)`, `M` the inverse of mirroring, scaling and rotating the image about the pivot. A scale of 0, or warp `levels` outside 1..4, SHALL raise an error. `vnoise.domain_affine(spec)` SHALL return the same map as six numbers `{ a, b, c, d, e, f }` (`c' = a c + b r + c`, `r' = d c + e r + f`), and `compile_domain` SHALL accept `affine = { ... }` (six numbers, else an error) in place of the transform fields, so callers can compose the map with their own cell mapping.

#### Scenario: Quarter turn
- **WHEN** a block is filled with `rotate = 90` about pivot `(0, 0)` and another without rotation
- **THEN** cell `(c, r)` of the rotated block equals cell `(r, -c)` of the unrotated one within 1e-5

#### Scenario: Magnification
- **WHEN** a block is filled with `scale = 2` about pivot `(0, 0)`
- **THEN** cell `(2c, 2r)` equals cell `(c, r)` of the unscaled block within 1e-5

#### Scenario: Mirror and translation
- **WHEN** a block is filled with `flip_x = true` about pivot `(10, 0)`, and another with `translate = {3, -2}`
- **THEN** cell `(c, r)` of the first equals unmirrored cell `(20 - c, r)`, and cell `(c, r)` of the second equals untranslated cell `(c - 3, r + 2)`

#### Scenario: Explicit affine
- **WHEN** a block is filled with `affine = vnoise.domain_affine(spec)` and another with `spec`
- **THEN** both blocks are identical
