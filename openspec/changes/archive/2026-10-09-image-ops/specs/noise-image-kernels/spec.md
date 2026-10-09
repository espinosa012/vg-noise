## ADDED Requirements

### Requirement: Valid-mode neighborhood kernels
Every kernel SHALL read a contiguous `sw x sh` float buffer and write a contiguous `(sw - 2R) x (sh - 2R)` buffer, where `R` is the kernel's border radius; output cell `(i, j)` corresponds to input cell `(i + R, j + R)` and SHALL only depend on input cells within the kernel window around it. A kernel SHALL do nothing when a pointer is NULL or the output would be empty.

#### Scenario: Output size
- **WHEN** a radius-2 kernel runs on a 10 x 8 buffer
- **THEN** it writes a 6 x 4 buffer

### Requirement: Convolution
The library SHALL export `vnoise_convolve(src, sw, sh, dst, kernel, r)` with a row-major `(2r + 1)^2` kernel (`dst = sum k[a][b] * src[i + b][j + a]`, correlation without flipping) and `vnoise_convolve_sep(src, sw, sh, dst, kx, ky, r)` applying the horizontal 1D kernel `kx` then the vertical `ky` (both `2r + 1` taps). The Lua binding SHALL offer stages `convolve` (explicit kernel, odd square size), `blur` (box, radius `r`), `gaussian` (`sigma`, radius `ceil(3 sigma)`, normalized), `sharpen` (`k`: kernel `[0,-k,0; -k,1+4k,-k; 0,-k,0]`), `emboss` (`k`: `k * [-1,-1,0; -1,0,1; 0,1,1]` added to the identity) and `laplacian` (`k`: `k * [0,1,0; 1,-4,1; 0,1,0]`).

#### Scenario: Identity kernel
- **WHEN** a 3 x 3 kernel with a single central 1 is applied
- **THEN** the output equals the input cropped by one cell

#### Scenario: Blur keeps constants
- **WHEN** a box or Gaussian blur runs on a constant buffer
- **THEN** every output equals that constant within 1e-6

### Requirement: Sobel
The library SHALL export `vnoise_sobel(src, sw, sh, dst, mode, k)` (radius 1) with `gx`, `gy` the standard Sobel responses divided by 4, and `mode` `VNOISE_SOBEL_MAG` (0) `k * sqrt(gx^2 + gy^2)`, `VNOISE_SOBEL_X` (1) `k * gx`, `VNOISE_SOBEL_Y` (2) `k * gy`. Stages: `sobel`, `sobel_x`, `sobel_y` with `k` (default 1).

#### Scenario: Step edge
- **WHEN** Sobel magnitude runs on a buffer that is 0 for columns < 5 and 1 otherwise
- **THEN** the cells whose window straddles the step give `1` (a cell next to the step) and cells away from it give `0`

### Requirement: Morphology
The library SHALL export `vnoise_morph(src, sw, sh, dst, op, r, shape)` and `int vnoise_morph_radius(int op, int r)` with ops `VNOISE_MORPH_ERODE` (0, min filter), `DILATE` (1, max filter), `OPEN` (2), `CLOSE` (3), `GRADIENT` (4, dilate - erode), `TOPHAT` (5, v - open), `BLACKHAT` (6, close - v) and shapes `VNOISE_SHAPE_SQUARE` (0) and `VNOISE_SHAPE_DISC` (1, offsets with `dx^2 + dy^2 <= r^2`). The border radius SHALL be `2r` for open, close, top-hat and black-hat and `r` otherwise. Stages: `erode`, `dilate`, `open`, `close`, `morph_gradient`, `tophat`, `blackhat` with `r` and `shape = "square" | "disc"` (default square).

#### Scenario: Dilate a point
- **WHEN** a single 1 in a 0 buffer is dilated with a square of radius 1
- **THEN** the output holds a 3 x 3 block of 1

#### Scenario: Opening removes specks
- **WHEN** a binary buffer with a filled 6 x 6 square and an isolated 1 is opened with radius 1
- **THEN** the isolated cell becomes 0 and the square is kept

#### Scenario: Closing fills holes
- **WHEN** a filled square with a one-cell hole is closed with radius 1
- **THEN** the hole becomes 1

### Requirement: Median and distance
The library SHALL export `vnoise_median(src, sw, sh, dst, r)` (median of the `(2r + 1)^2` window) and `vnoise_distance(src, sw, sh, dst, r, t)` returning `min(d, r) / r`, `d` the Euclidean distance to the nearest cell with `v >= t` in the disc of radius `r` (radius `r`). Stages: `median` (`r`), `distance` (`r`, `t` default 0.5).

#### Scenario: Median removes salt
- **WHEN** a radius-1 median runs on a constant 0.2 buffer with one cell at 1
- **THEN** every output is 0.2

#### Scenario: Distance field
- **WHEN** `distance(4, 0.5)` runs on a buffer with a single cell at 1
- **THEN** that cell gives 0, a cell 2 cells away gives 0.5 and cells farther than 4 give 1
