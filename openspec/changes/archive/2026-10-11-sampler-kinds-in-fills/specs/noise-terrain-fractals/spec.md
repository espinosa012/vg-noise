## ADDED Requirements

### Requirement: Every fill accepts every sampler kind
`vnoise.fill_grid`, `vnoise.fill_domain` and `vnoise.fill_pipeline` SHALL accept every `fill_sampler` kind as their `kind`. For `damped` and the cellular kinds they SHALL read `jitter` and `damping` from `opts` (defaults 1), and evaluate through `vnoise_fill_sampler`:
- `fill_grid`: with the identity domain, cell `(i, j)` at `(ox + i * freq, oy + j * freq)`;
- `fill_domain` and `fill_pipeline`: through their domain.

`fbm`, `ridge` and `turb` SHALL keep their dedicated native fills, with outputs bit-identical to earlier versions. An unknown kind SHALL raise an error naming it.

#### Scenario: Same values as fill_sampler
- **WHEN** each new kind is filled through `fill_grid`, `fill_domain` (rotated, warped domain) and `fill_pipeline` (no stages, `clamp = false`)
- **THEN** the values equal `fill_sampler` with the same parameters within 1e-6

#### Scenario: Jitter reaches the fill
- **WHEN** `cell_f1` is filled with `jitter = 0` and with `jitter = 1`
- **THEN** the buffers differ

#### Scenario: New kinds tile in pipelines
- **WHEN** a `cell_edge` pipeline with a Gaussian and `gullies` is filled as one 64 x 64 block and as four 32 x 32 blocks
- **THEN** every cell agrees within 1e-5
