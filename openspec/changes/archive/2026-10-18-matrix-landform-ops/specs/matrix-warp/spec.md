## ADDED Requirements

### Requirement: Warp by displacement matrices
The library SHALL export `vnoise_warp_matrix(const float* src, int w, int h, float* dst, const float* dx, const float* dy, const float* strength, const vnoise_warp_t* wp)`. Each `dst(i, j)` SHALL be `src` sampled at index-space point `(i + amp * ux, j + amp * uy)` with clamped edges, bilinear or Catmull-Rom clamped to the 2 x 2 neighborhood (`filter`), clamped to 0..1. With `dx` and `dy`, `u = 2 * (d - 0.5)` per axis. With `dx` only, `dx` SHALL be a direction (0..1 one turn clockwise from +x on a y-down screen) and `u` its unit vector times `strength` (1 when NULL). With neither, `dst` SHALL equal `src`. It SHALL do nothing for NULL buffers, non-positive sizes or `dst == src`.

#### Scenario: Neutral displacement
- **WHEN** a matrix is warped with `dx` and `dy` all 0.5
- **THEN** the result equals the matrix

#### Scenario: Uniform shift
- **WHEN** a matrix is warped with `dx` all 1, `dy` all 0.5 and `amp` 3
- **THEN** cell `(i, j)` equals the source cell `(i + 3, j)` wherever that cell exists

#### Scenario: Direction field
- **WHEN** a matrix is warped with a direction of 0.25 and `amp` 2
- **THEN** cell `(i, j)` equals the source cell `(i, j + 2)`; with `strength` all 0 the result equals the matrix

### Requirement: Warp by a seeded field
The library SHALL export `vnoise_warp_matrix_noise(const float* src, int w, int h, float* dst, const noise_state_t* s, const vnoise_warp_t* wp)`, displacing cell `(i, j)` exactly as `vnoise_fill_domain` would with an identity affine and the warp `amp`, `freq`, `octaves`, `lac`, `gain`, `base` and `levels` of `wp`. The result SHALL be deterministic for equal inputs and seed, and `amp = 0` SHALL leave the matrix unchanged.

#### Scenario: Deterministic and seeded
- **WHEN** the same matrix is warped twice with seed 3 and once with seed 4
- **THEN** the first two results are identical and differ from the third

### Requirement: Warp in Lua
The binding SHALL provide `vnoise.warp(m, w, h, spec)` returning a new matrix (or `spec.out`): `dx` and `dy`, or `direction` with optional `strength`, or the noise warp (`freq` 1/64, `octaves` 3, `lac` 2, `gain` 0.5, `base`, `levels` 1..4, `state` or `seed`), with `amp` (default 1/16 of the shorter side) and `filter` ("bilinear", "bicubic"). Only one of `dx`/`dy`, or `out` equal to the source, SHALL raise an error.

#### Scenario: No overshoot
- **WHEN** a step from 0 to 0.8 is warped with the bicubic filter
- **THEN** every value stays in 0..0.8
