## Why

The game that consumes vg-noise (ludum) treats a block of noise values as a grayscale image in 0..1 and wants classic image processing on it: geometric transforms (rotation, scaling, mirroring, domain warping), inversion and binarization, convolutions (blur, sharpen, emboss, edge detection), binary and grayscale morphology (erosion, dilation, opening, closing, gradient, top-hat), median filtering and bounded distance fields, each applicable to the whole image or to a region.

Today the library only has pointwise value operations, which is what lets the game sample its maps chunk by chunk (maps up to 16384 x 16384 cells, no whole-map buffer): a cell's value depends only on its coordinate. Neighborhood operations and region masks must keep that property: the value of a cell must not depend on which block it was computed in.

## What Changes

- **More pointwise ops** in the existing chain: `invert`, `threshold` (binarize), `smoothstep`, `gamma`, `quantize`, `clamp`.
- **Domain transforms** applied to sample coordinates before evaluating the noise (exact, no resampling, chunk-safe): an affine map in cell space (rotation, scale, mirroring and translation about a pivot) and optional fBm domain warping. New C entry `vnoise_fill_domain`, which samples cells by absolute integer index.
- **Neighborhood kernels** over float buffers in *valid* mode (an input of `sw x sh` gives `(sw - 2r) x (sh - 2r)`): generic and separable convolution, Sobel (magnitude, x, y), grayscale morphology with square or disc structuring elements (erode, dilate, open, close, gradient, top-hat, black-hat), median, and a bounded distance field.
- **Region masks** (rectangle, ellipse, polygon in absolute cell coordinates, or a value range) with optional feather and inversion; a masked stage blends its output with its input.
- **A pipeline** (`vnoise.compile_pipeline` / `vnoise.fill_pipeline` in the Lua binding): domain + ordered stages (point ops, kernels, each with an optional mask) evaluated for any block of absolute cells. It samples the block with an apron equal to the sum of the kernel radii and crops while running, so any tiling of a region gives the same values as one call over the whole region.
- **Global statistics as point ops**: Lua helpers to build a histogram of a probe buffer, Otsu's threshold and a histogram-equalization LUT, which then run as ordinary (chunk-safe) point ops.
- Existing functions keep their signatures and output.

## Capabilities

### New Capabilities
- `noise-domain`: domain transforms (affine + warp) and absolute-cell sampling.
- `noise-image-kernels`: valid-mode neighborhood kernels on float buffers.
- `noise-pipeline`: pipeline compilation and block evaluation with apron, region masks, global-statistics helpers.

### Modified Capabilities
- `noise-value-ops`: new pointwise op ids and names.

## Non-goals

- Whole-image operations that cannot be expressed per block (connected-component labeling, unbounded distance transforms, flood fill). They break block independence; a later change may add them for finite buffers only.
- Pipelines with several inputs (blending two noises, masks taken from another noise). The stage format leaves room for them.
- Using any of this from the game (recipe format v3, Map Editor UI). That is a separate change in ludum.

## Impact

- `cpp/include/vnoise/vnoise.h`, `internal.h`; new `cpp/src/domain.cpp`, `cpp/src/kernels.cpp`, `cpp/src/mask.cpp`.
- `lua/vnoise.lua` (cdefs, op names, pipeline, statistics helpers). Ludum picks it up with `make build-noise`.
- New `tests/image_ops.lua`, run by `make test`; `README.md`.
