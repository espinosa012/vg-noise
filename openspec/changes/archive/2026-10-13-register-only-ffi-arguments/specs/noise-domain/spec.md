## MODIFIED Requirements

### Requirement: Absolute cell sampling with a domain transform
The library SHALL export `void vnoise_fill_domain(const noise_state_t* s, const vnoise_sampler_t* sp, float* out, int c0, int r0, int w, int h, const vnoise_domain_t* d)`, which reads `mode`, `base`, `octaves`, `lac` and `gain` from `sp`, with `vnoise_domain_t { float m[6]; float ox, oy, freq; float warp_amp, warp_freq; int warp_octaves; int warp_base; }`. For every `0 <= i < w`, `0 <= j < h`, with `c = c0 + i`, `r = r0 + j`, it SHALL set `out[j * w + i]` to the fractal sample (`mode` 0 fBm, 1 ridge, 2 turbulence) at `(ox + c'' * freq, oy + r'' * freq)`, where `(c', r') = (m0 c + m1 r + m2, m3 c + m4 r + m5)` and `(c'', r'')` is `(c', r')` displaced by `warp_amp` times two fBm samples of the warp field at `(c' * warp_freq + 5.2, r' * warp_freq + 1.3)` and `(c' * warp_freq + 1.7, r' * warp_freq + 9.2)` when `warp_amp != 0` (`warp_octaves` octaves, lacunarity 2, gain 0.5, base `warp_base`). It SHALL do nothing for NULL pointers, non-positive sizes or a mode other than 0, 1 and 2. A cell's value SHALL depend only on its absolute index and the arguments other than `c0`, `r0`, `w`, `h`.

#### Scenario: Identity matches the grid fill
- **WHEN** `vnoise_fill_domain` runs with the identity affine, no warp and origin `(ox, oy)` over cells from `(c0, r0)`
- **THEN** every value equals `fill_grid` with origin `(ox + c0 * freq, oy + r0 * freq)` within 1e-5

#### Scenario: Overlapping blocks agree
- **WHEN** a 40 x 40 block from `(0, 0)` and a 20 x 20 block from `(17, 9)` are filled with the same rotated and warped domain
- **THEN** the shared cells have the same values within 1e-5
