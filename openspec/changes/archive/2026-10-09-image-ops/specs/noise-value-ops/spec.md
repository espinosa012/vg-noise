## ADDED Requirements

### Requirement: Extended point operations
The library SHALL implement these additional value ops, usable in every op chain, applied to a value `v`:
- `VNOISE_OP_INVERT` (5): `1 - v`.
- `VNOISE_OP_THRESHOLD` (6): `1` when `v >= p[0]`, else `0`.
- `VNOISE_OP_SMOOTHSTEP` (7): `t = clamp01((v - p[0]) / (p[1] - p[0]))`, result `t * t * (3 - 2t)`; when `p[1] == p[0]` it behaves as `THRESHOLD(p[0])`.
- `VNOISE_OP_GAMMA` (8): `max(v, 0) ^ p[0]`.
- `VNOISE_OP_QUANTIZE` (9): with `n = floor(p[0])` levels (`n >= 2`; smaller values leave `v` unchanged), `x = clamp01(v)`, result `min(floor(x * n), n - 1) / (n - 1)`.
- `VNOISE_OP_CLAMP` (10): `min(max(v, p[0]), p[1])`.
The Lua binding SHALL accept the names `"invert"`, `"threshold"`, `"smoothstep"`, `"gamma"`, `"quantize"` and `"clamp"` and expose the matching `vnoise.OP_*` constants.

#### Scenario: Invert
- **WHEN** `invert` is applied to `0.3`
- **THEN** the result is `0.7`

#### Scenario: Threshold
- **WHEN** `threshold(0.5)` is applied to `0.49`, `0.5` and `0.8`
- **THEN** the results are `0`, `1` and `1`

#### Scenario: Smoothstep
- **WHEN** `smoothstep(0.2, 0.6)` is applied to `0.1`, `0.4` and `0.9`
- **THEN** the results are `0`, `0.5` and `1`

#### Scenario: Gamma
- **WHEN** `gamma(2)` is applied to `0.5` and to `-0.3`
- **THEN** the results are `0.25` and `0`

#### Scenario: Quantize
- **WHEN** `quantize(4)` is applied to `0.1`, `0.3`, `0.74` and `1`
- **THEN** the results are `0`, `1/3`, `2/3` and `1`

#### Scenario: Explicit clamp
- **WHEN** the chain `[scale(3), clamp(0, 1), offset(-0.5)]` is applied to `0.5` without final clamp
- **THEN** the result is `0.5`
