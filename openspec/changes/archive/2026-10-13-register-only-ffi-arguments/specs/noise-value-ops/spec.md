## MODIFIED Requirements

### Requirement: Fused image fill with ops
The library SHALL export `fbm2_fill_imagedata_ops_rgba8`, `ridge2_fill_imagedata_ops_rgba8` and `turb2_fill_imagedata_ops_rgba8`, taking the same arguments as the existing image fills but a `const vnoise_chain_t*` (`{ const vnoise_op_t* ops; int n; const float* data; }`, NULL for the empty chain) instead of `lo`/`hi`. In both families the color SHALL be one `unsigned int rgba = r | g << 8 | b << 16 | a << 24` (`VNOISE_RGBA`), the last argument. Each pixel SHALL be `t = clamp01(chain(noise))` written as `(r·t, g·t, b·t, a)`, exactly as the existing fills write `t`.

#### Scenario: Equivalent to lo/hi fill
- **WHEN** an image is filled with the ops variant and the chain `[remap(lo, hi)]`, and another with the existing fill and `lo`, `hi`
- **THEN** both images are identical
