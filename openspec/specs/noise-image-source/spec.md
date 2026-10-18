# noise-image-source Specification

## Purpose
Define grayscale image files (and raw pixel buffers) as a noise sampler kind, so an image takes part in domains, point and kernel ops, masks, pipelines and source trees exactly like fBm or cellular noise.

## Requirements

### Requirement: Image loading
The library SHALL load PNG, JPEG, BMP, TGA and PGM/PNM files as grayscale floats in 0..1 with row 0 on top (`vnoise_image_load`, Lua `vnoise.load_image(path)`). Colour files SHALL be converted to luminance and 16-bit files SHALL keep their precision (value / 65535). `vnoise.image_from_pixels(data, w, h, channels, bytes)` SHALL build an image from raw row-major pixels (1, 2 or 4 bytes per channel; 3 or 4 channels use luminance), copying them. A missing or undecodable file and a bad pixel format SHALL raise an error naming the reason.

#### Scenario: 16-bit precision
- **WHEN** a 16-bit grayscale PNG holds the values 1 and 65535
- **THEN** the loaded pixels are 1/65535 and 1

#### Scenario: Unreadable file
- **WHEN** `load_image` is given a missing path or a file that is not an image
- **THEN** it raises an error

### Requirement: Image sampler kind
`"image"` SHALL be a sampler kind accepted wherever a kind is (`fill_sampler`, `fill_grid`, `fill_domain`, `fill_pipeline`, source leaves) with `image` (a path or a loaded image), `filter` (`"nearest"`, `"bilinear"` (default), `"bicubic"`) and `wrap` (`"clamp"` (default), `"repeat"`, `"mirror"`). The sample point is in pixel units and integer coordinates are pixel values; `freq` defaults to 1 for this kind, so cell `(c, r)` reads pixel `(c, r)`. The domain (rotation, scaling, warping) applies as for any sampler, so a cell's value depends only on its absolute index and any tiling equals one call within 1e-5. Octaves, lacunarity and gain are ignored. NaN, infinite or huge coordinates SHALL give 0. A path given as `image` SHALL be kept alive as long as the compiled sampler.

#### Scenario: Exact pixels
- **WHEN** an image is filled with the kind `image`, the default `freq` and no domain
- **THEN** every cell equals its pixel

#### Scenario: Wrap modes
- **WHEN** a 4 pixel wide image is sampled with `nearest` at x = 4 and x = -1
- **THEN** `repeat` gives pixels 0 and 3, `mirror` gives pixels 3 and 0, and `clamp` gives pixels 3 and 0 (the nearest edge pixel)

#### Scenario: Operations
- **WHEN** an image leaf is combined with `fbm` in a source tree, or used as a pipeline source with a blur stage
- **THEN** the ops, combinators and kernel stages apply to its values as to any noise
