## MODIFIED Requirements

### Requirement: Region masks
A stage's `mask` SHALL be `{ "rect", x0, y0, x1, y1 }` (inclusive absolute cell bounds), `{ "ellipse", cx, cy, rx, ry }`, `{ "polygon", { x1, y1, x2, y2, ... } }` (at least three vertices, even-odd rule) or `{ "range", lo, hi }` (on the stage input), with optional `feather` (default 0) and `invert` (default false). The weight `m` SHALL be 1 inside and 0 outside, faded over `feather` inside the boundary, and `1 - m` when inverted; the stage result SHALL be `before + m * (after - before)`, `before` the stage input at the same cell. The C side SHALL export `vnoise_mask_blend(float* dst, int w, int h, const float* before, int before_stride, int c0, int r0, const vnoise_mask_t* mask)`; a polygon mask SHALL carry its vertex pool in `vnoise_mask_t.data`.

#### Scenario: Rectangle mask
- **WHEN** `invert` runs with mask `{ "rect", 2, 2, 5, 5 }` on a constant 0.2 block
- **THEN** cells inside the rectangle are 0.8 and the others 0.2

#### Scenario: Inverted mask
- **WHEN** the same stage has `invert = true`
- **THEN** cells inside are 0.2 and the others 0.8

#### Scenario: Feather
- **WHEN** the mask is `{ "rect", 0, 0, 20, 20, feather = 4 }`
- **THEN** cell `(2, 10)` blends half way (weight 0.5) and cell `(10, 10)` fully

#### Scenario: Range mask
- **WHEN** `scale(0)` runs with mask `{ "range", 0.4, 0.6 }`
- **THEN** values in 0.4..0.6 become 0 and the others are unchanged
