## ADDED Requirements

### Requirement: Seeded white-noise grid fill
The library SHALL provide `white2_fill_grid(const noise_state_t* s, float* out, int ox, int oy, int w, int h)` writing `white2_eval(s, ox + i, oy + j)` to `out[j * w + i]` for `0 <= i < w`, `0 <= j < h`, and SHALL do nothing for a null state or buffer or a non-positive size. The Lua binding SHALL expose it as `vnoise.fill_white(state, opts)` with `w`, `h` (default 256), `ox`, `oy` (default 0), optional `out`, and optional `ops`/`clamp` applied as in `fill_grid`.

#### Scenario: Batch fill matches per-cell evaluation
- **WHEN** a 16 x 16 grid is filled at origin (100, 200)
- **THEN** every value equals `state:white2` at the same cell

#### Scenario: Seed changes the field
- **WHEN** the same block is filled with seeds 1 and 2
- **THEN** the grids differ

#### Scenario: Negative origins
- **WHEN** a block is filled at origin (-2, -7)
- **THEN** its values equal `state:white2` at the same negative cells

#### Scenario: Op chain
- **WHEN** the fill is given `ops = { { "remap", -1, 1 } }`
- **THEN** every value equals `(white + 1) / 2` and lies in [0, 1]
